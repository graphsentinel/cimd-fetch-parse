#!/usr/bin/env bash
# Shared functions for checks/*.sh. Sourced, not run.
#
# Exit contract of every check:
#   0  PASS     the observed results are the ones the claim states
#   1  FAIL     a completed observation contradicts the claim (including an unexpected refusal or a 5xx answer)
#   77 NOT RUN  setup or input missing — never a result. "NOT RUN [vendor-fetch]" means Keycloak (or the check) could
#               not fetch a published document (a java.net exception in the server log); scripts/lab.sh retries only
#               that tag. Every other NOT RUN is final.
#
# Every authorization and registration request goes through auth() / anon_register(): one request gives the HTTP
# status, the message shown to the caller (same response) and, from the Keycloak server log of the container that
# answered, bounded to that request's time window, the server's own reason. Each request is also written to
# $OBS_FILE, and scripts/summary.py compares that list with the recording proxy's raw record.
#
# Environment (set by scripts/lab.sh test): ENGINE, MD, SCENARIOS, RESULTS, OBS_FILE, RUN_ID, CHECK,
#   KC_STOCK/C_STOCK (stock Keycloak), KC_EXT/C_EXT (same version + this repository's extension jar),
#   KC_NOFLAG/C_NOFLAG (same version, CIMD feature not enabled).
LAB=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENGINE=${ENGINE:-podman}
RESULTS=${RESULTS:-$LAB/results/measurements.tsv}
OBS_FILE=${OBS_FILE:-/dev/null}
RUN_ID=${RUN_ID:-manual}
CHECK=${CHECK:-$(basename "$0" .sh)}
KC=${KC:-${KC_STOCK:-}}
ADMIN_USER=${ADMIN_USER:-lab-admin}; ADMIN_PASSWORD_FILE=${ADMIN_PASSWORD_FILE:-$LAB/lab/.runtime/admin-password}  # per-checkout, generated at install
PROFILE=cimd-lab; POLICY=cimd-lab-policy
REG_POLICY=org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy

BAD=(); NETS=()   # contradictions and unfetched documents collected so far (see expect / settle)
fail(){ echo "FAIL: $*"; exit 1; }
# Every NOT RUN first honours contradictions already observed: a later setup or fetch problem never hides them.
not_run(){ [ ${#BAD[@]} -eq 0 ] || fail "$(printf '%s; ' "${BAD[@]}")(then: $*)"; echo "NOT RUN: $*"; exit 77; }
not_run_fetch(){ [ ${#BAD[@]} -eq 0 ] || fail "$(printf '%s; ' "${BAD[@]}")(then: $*)"; echo "NOT RUN [vendor-fetch]: $*"; exit 77; }
# sub <var> <function> <args...>: run a function in a subshell and keep its NOT RUN / FAIL (a plain $(...) loses them)
sub(){ local __v=$1 __o __rc; shift; __o=$("$@"); __rc=$?
  if [ $__rc != 0 ]; then printf '%s\n' "$__o" | grep -E '^(NOT RUN|FAIL)' | tail -1; exit $__rc; fi
  printf -v "$__v" '%s' "$__o"; }
utc(){ date -u +%FT%T.%NZ; }

token(){ # token [base-url] -> admin access token (60 s lifetime: refreshed before every admin step)
  local t; t=$(curl -s --max-time 10 -X POST "${1:-$KC}/realms/master/protocol/openid-connect/token" \
    --data-urlencode grant_type=password --data-urlencode client_id=admin-cli \
    --data-urlencode "username=$ADMIN_USER" --data-urlencode "password@$ADMIN_PASSWORD_FILE" | jq -r '.access_token // empty')
  [ -n "$t" ] || return 1; printf '%s' "$t"; }
refresh(){ TOKEN=$(token) || not_run "no admin token from $KC"; }
bearer(){ printf 'Authorization: Bearer %s' "$TOKEN"; }
kc(){ curl -s --max-time 60 -H "$(bearer)" "$@"; }                         # admin REST call
kc_status(){ curl -s -o /dev/null -w '%{http_code}' --max-time 60 -H "$(bearer)" "$@"; }

server_version(){ # server_version [base-url]
  local u=${1:-$KC} t; t=$(token "$u") || { echo unknown; return; }
  curl -s --max-time 10 -H "@"<(printf 'Authorization: Bearer %s\n' "$t") "$u/admin/serverinfo" | jq -r '.systemInfo.version // "unknown"'; }
setup_label(){ # from the server itself (never from the port): "extension" when lenient-cimd is installed
  local v t e; v=$(server_version); t=$(token) || { echo "unknown-$v"; return; }
  e=$(curl -s --max-time 10 -H "@"<(printf 'Authorization: Bearer %s\n' "$t") "$KC/admin/serverinfo" \
      | jq -r '.providers["client-policy-executor"].providers // {} | has("lenient-cimd")')
  case "$e" in true) echo "extension-$v";; false) echo "stock-$v";; *) echo "unknown-$v";; esac; }

record(){ # record <field> <value> ...  -> results/measurements.tsv (one row per field)
  [ -n "${SETUP:-}" ] || SETUP=$(setup_label)
  mkdir -p "$(dirname "$RESULTS")"
  [ -s "$RESULTS" ] || printf 'utc\trun_id\tcheck\tsetup\tfield\tvalue\n' > "$RESULTS"
  while [ $# -ge 2 ]; do printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(utc)" "$RUN_ID" "$CHECK" "$SETUP" "$1" "$2" >> "$RESULTS"; shift 2; done; }
observe(){ jq -nc --arg k "$1" --arg r "$2" --arg c "$3" --arg s "$4" '{kind:$k, realm:$r, client_id:$c, status:$s}' >> "$OBS_FILE"; }

sorted_csv(){ printf '%s\n' "$@" | LC_ALL=C sort | paste -sd, -; }
json_array(){ printf '%s\n' "$@" | jq -R . | jq -sc .; }
loaded_executor(){ kc "$KC/admin/realms/$1/client-policies/profiles" | jq -r "[.profiles[]?|select(.name==\"$PROFILE\")|.executors[0].executor]|first // \"-\""; }
loaded_hosts(){ kc "$KC/admin/realms/$1/client-policies/profiles" \
  | jq -r "[.profiles[]?|select(.name==\"$PROFILE\")|.executors[0].configuration[\"cimd-allow-permitted-domains\"][]?]|.[]" | LC_ALL=C sort | paste -sd, -; }
policy_active(){ kc "$KC/admin/realms/$1/client-policies/policies" \
  | jq -r --arg p $POLICY --arg pr $PROFILE '[.policies[]?|select(.name==$p and .enabled==true and ((.profiles//[])|index($pr)!=null))]|length'; }

realm_fresh(){ # realm_fresh <realm>: delete if present, create, and prove it is new (no clients beyond the built-ins)
  local s; refresh
  s=$(kc_status -X DELETE "$KC/admin/realms/$1"); case "$s" in 204|404) ;; *) not_run "realm $1: delete answered $s";; esac
  sleep 1
  s=$(kc_status -X POST "$KC/admin/realms" -H 'Content-Type: application/json' -d "{\"realm\":\"$1\",\"enabled\":true}")
  [ "$s" = 201 ] || not_run "realm $1: create answered $s"
  local n; n=$(cimd_count "$1") || not_run "realm $1: cannot list clients"; [ "$n" = 0 ] || not_run "realm $1 is not new ($n CIMD clients)"; }
realm_setup(){ # realm_setup <realm> <allowlist-json-array> [executor]: new realm with the CIMD policy, verified
  local r=$1 hosts=$2 ex=${3:-client-id-metadata-document} s want
  realm_fresh "$r"
  s=$(kc_status -X PUT "$KC/admin/realms/$r/client-policies/profiles" -H 'Content-Type: application/json' \
    -d "{\"profiles\":[{\"name\":\"$PROFILE\",\"executors\":[{\"executor\":\"$ex\",\"configuration\":{\"cimd-allow-http-scheme\":false,\"cimd-allow-permitted-domains\":$hosts}}]}]}")
  [ "$s" = 204 ] || not_run "realm $r: profile answered $s"
  s=$(kc_status -X PUT "$KC/admin/realms/$r/client-policies/policies" -H 'Content-Type: application/json' \
    -d "{\"policies\":[{\"name\":\"$POLICY\",\"enabled\":true,\"conditions\":[{\"condition\":\"any-client\",\"configuration\":{}}],\"profiles\":[\"$PROFILE\"]}]}")
  [ "$s" = 204 ] || not_run "realm $r: policy answered $s"
  sleep 1
  [ "$(loaded_executor "$r")" = "$ex" ] || not_run "realm $r: executor $ex not loaded"
  want=$(printf '%s' "$hosts" | jq -r '.[]' | LC_ALL=C sort | paste -sd, -)
  [ "$(loaded_hosts "$r")" = "$want" ] || not_run "realm $r: allowlist not loaded"
  [ "$(policy_active "$r")" = 1 ] || not_run "realm $r: CIMD policy not active"; }

clients_json(){ # clients_json <realm> -> JSON array (fails instead of returning an error object)
  refresh; local j; j=$(kc "$KC/admin/realms/$1/clients?max=5000")
  [ "$(printf '%s' "$j" | jq -r type 2>/dev/null)" = array ] || return 1; printf '%s' "$j"; }
cimd_count(){ local j; j=$(clients_json "$1") || return 1; printf '%s' "$j" | jq '[.[]|select(.clientId|test("^https?://"))]|length'; }
cimd_ids(){ local j; j=$(clients_json "$1") || return 1
  printf '%s' "$j" | jq -r '.[].clientId|select(test("^https?://"))' | LC_ALL=C sort | paste -sd, -; }

server_log(){ "$ENGINE" logs --since "$2" ${3:+--until "$3"} "$1" 2>&1 || true; }  # server_log <container> <since> [until]
cause(){ # cause <log text> -> the server's own reason for a refusal
  local l=$1
  if [[ $l =~ Unrecognized\ field\ \"([A-Za-z_]+)\" ]]; then echo "PARSE:${BASH_REMATCH[1]}"
  elif [[ $l == *"HTTP connection failure: java.net."* || $l =~ could\ not\ obtain\ client\ metadata\ from\ [^[:space:]]+:\ (SocketTimeout|Connect|UnknownHost|NoRouteToHost)Exception ]]; then echo NETWORK
  elif [[ $l =~ not\ trusted\ domain:\ host\ =\ ([^[:space:],;]+) ]]; then echo "DOMAIN:${BASH_REMATCH[1]}"
  elif [[ $l == *JsonMappingException* || $l == *JsonParseException* ]]; then echo MALFORMED_JSON
  elif [[ $l == *"does not include client_id"* ]]; then echo CLIENT_ID_MISSING
  elif [[ $l == *"client_id property in client metadata does not exactly match"* ]]; then echo CLIENT_ID_MISMATCH
  elif [[ $l == *"redirect_uri parameter does not exactly match"* ]]; then echo REDIRECT_MISMATCH
  else echo UNKNOWN; fi; }

auth(){ # auth <realm> <client_id> <redirect_uri> <container>
  # sets H (HTTP status), PAGE (login: the response is Keycloak's login form | error: an error page | other),
  # MSG (error text shown to the caller, same response), CAUSE (server log reason, "-" if accepted),
  # WINDOW (the server log for this request only: [1 s before, 1 s after])
  local f t0 t1; f=$(mktemp); t0=$(utc); sleep 1
  H=$(curl -s -o "$f" -w '%{http_code}' --max-time 30 \
    "$KC/realms/$1/protocol/openid-connect/auth?client_id=$(jq -rn --arg v "$2" '$v|@uri')&redirect_uri=$(jq -rn --arg v "$3" '$v|@uri')&response_type=code&scope=openid&state=lab")
  MSG=$(grep -oiE "Client not found|Client Metadata fetch failed|invalid_[a-z]+" "$f" | head -1 || true)
  if grep -q 'id="kc-form-login"' "$f" && [ -z "$MSG" ]; then PAGE=login; elif [ -n "$MSG" ]; then PAGE=error; else PAGE=other; fi
  rm -f "$f"
  sleep 1; t1=$(utc)
  WINDOW=$(server_log "$4" "$t0" "$t1")
  case "$H" in 200) [ $PAGE = login ] && CAUSE=- || CAUSE=$(cause "$WINDOW");; *) CAUSE=$(cause "$WINDOW");; esac
  observe auth "$1" "$2" "$H"; }
# outcome of the last auth(): accepted (HTTP 200 with the login form) | refused (4xx) | network | error (anything else,
# including a 5xx answer or a 2xx/3xx that is not the login form: a contradiction for every expectation)
outcome(){ case "$H" in 200) [ $PAGE = login ] && echo accepted || echo error;; 4*) [ "$CAUSE" = NETWORK ] && echo network || echo refused;; 000) echo network;; *) echo error;; esac; }
# expect <label> <accepted | refused | parse[:FIELD] | cause:<CAUSE> | parse-or-accepted>  judges the last auth().
# Contradictions are collected in BAD, documents that never arrived in NETS; settle() decides once at the end, so a
# contradiction is never hidden behind another document's network failure.
expect(){
  local o; o=$(outcome)
  if [ "$o" = network ]; then NETS+=("$1"); return; fi
  case "$2" in
    accepted) [ "$o" = accepted ] || BAD+=("$1: expected accepted, got HTTP $H $CAUSE");;
    refused) [ "$o" = refused ] || BAD+=("$1: expected refused, got HTTP $H $CAUSE");;
    parse-or-accepted) { [ "$o" = accepted ] || { [ "$o" = refused ] && [[ $CAUSE == PARSE:* ]]; }; } || BAD+=("$1: refused for another reason (HTTP $H $CAUSE)");;
    parse|parse:*) local f=${2#parse}; f=${f#:}
            { [ "$o" = refused ] && [[ $CAUSE == PARSE:${f}* ]]; } || BAD+=("$1: expected a parse refusal${f:+ on $f}, got HTTP $H $CAUSE");;
    cause:*) { [ "$o" = refused ] && [ "$CAUSE" = "${2#cause:}" ]; } || BAD+=("$1: expected ${2#cause:}, got HTTP $H $CAUSE");;
    *) BAD+=("$1: unknown expectation '$2'");;
  esac; }
settle(){ [ ${#BAD[@]} -eq 0 ] || fail "$(printf '%s; ' "${BAD[@]}")"
  [ ${#NETS[@]} -eq 0 ] || not_run_fetch "not fetched by Keycloak (network): ${NETS[*]}"; }

set_trusted_hosts(){ # set_trusted_hosts <realm> <json-array>: [] locks anonymous registration; verified by read-back
  local id s; refresh
  id=$(kc "$KC/admin/realms/$1/components?type=$REG_POLICY" | jq -r '.[]|select(.providerId=="trusted-hosts" and .subType=="anonymous")|.id')
  [ -n "$id" ] || not_run "realm $1: no trusted-hosts policy"
  s=$(kc "$KC/admin/realms/$1/components/$id" \
    | jq --argjson h "$2" '.config["trusted-hosts"]=$h | .config["host-sending-registration-request-must-match"]=["true"] | .config["client-uris-must-match"]=["false"]' \
    | kc_status -X PUT "$KC/admin/realms/$1/components/$id" -H 'Content-Type: application/json' -d @-)
  [ "$s" = 204 ] || not_run "realm $1: trusted-hosts update answered $s"
  [ "$(kc "$KC/admin/realms/$1/components/$id" | jq -c '.config["trusted-hosts"] // [] | sort')" = "$(jq -c sort <<<"$2")" ] || not_run "realm $1: trusted-hosts not applied"; }
anon_register(){ # anon_register <realm>: sets DS (HTTP status) and DP (policy named in the refusal, "-" if none)
  local f; f=$(mktemp)
  DS=$(curl -s -o "$f" -w '%{http_code}' --max-time 30 -X POST "$KC/realms/$1/clients-registrations/openid-connect" \
    -H 'Content-Type: application/json' -d '{"client_name":"anonymous-lab-client","redirect_uris":["http://127.0.0.1/callback"]}')
  DP=$(grep -oE "Policy '[^']+'" "$f" | head -1 || true); DP=${DP:--}; rm -f "$f"
  observe register "$1" - "$DS"; }

fetch_doc(){ # fetch_doc <url> -> the published document, or nothing when it is not a CIMD document
  local j; j=$(curl -sL --max-time 20 -H 'Accept: application/json' "$1" 2>/dev/null)
  printf '%s' "$j" | jq -e .client_id >/dev/null 2>&1 && printf '%s' "$j"; }
uri_hosts(){ # stdin: documents -> hosts of every *uri* property (IPv6 literals left out; see extract-hosts.py)
  jq -r 'to_entries[]|select(.key|test("uri"))|.value|if type=="array" then .[] else . end' | "$LAB/scripts/extract-hosts.py"; }

# The eight published CIMD client identities (fetched live from their publishers on every run).
VENDOR_DOCS=(
  "openai-chatgpt|https://chatgpt.com/oauth/client.json"
  "openai-codex|https://chatgpt.com/oauth/codex/client.json"
  "openai-atlas|https://chatgpt.com/oauth/atlas/client.json"
  "opencode|https://opencode.ai/oauth/opencode/client.json"
  "vscode|https://vscode.dev/oauth/client-metadata.json"
  "copilot-cli|https://github.com/copilot/cli/client-metadata.json"
  "hermes-agent|https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json"
  "goose|https://goose-docs.ai/oauth/client-metadata.json"
)
declare -A DOC
fetch_vendor_docs(){ # fills DOC[name]; a document that cannot be fetched means the check cannot run
  local d; for d in "${VENDOR_DOCS[@]}"; do DOC[${d%%|*}]=$(fetch_doc "${d##*|}"); [ -n "${DOC[${d%%|*}]}" ] || not_run_fetch "could not fetch ${d##*|}"; done; }
fetch_or_skip(){ local j; j=$(fetch_doc "$1"); [ -n "$j" ] || not_run_fetch "could not fetch $1"; printf '%s' "$j"; }
all_vendor_hosts(){ local n; for n in "${!DOC[@]}"; do printf '%s\n' "${DOC[$n]}"; done | uri_hosts; }
cid_of(){ jq -r .client_id <<<"${DOC[$1]}"; }
ru_of(){ jq -r '.redirect_uris[0]' <<<"${DOC[$1]}"; }
md_host(){ printf '%s' "${MD#https://}" | cut -d: -f1; }
