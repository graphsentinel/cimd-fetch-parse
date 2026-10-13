#!/usr/bin/env bash
# Layer 2: the lab. build | install | uninstall | reinstall | status | test | summary | all
#
# Per Keycloak version (VERSIONS, default "26.7.0 26.8.0") three containers, each bound to 127.0.0.1:<port>:
#   stock   --features=cimd
#   ext     --features=cimd + this repository's jar (lenient-cimd executor, logging-cimd provider selected)
#   noflag  CIMD feature not enabled (check 07 compares the advertisement)
# In front of each a recording proxy on 127.0.0.2:<same port>; checks talk to the proxy. A local HTTPS metadata
# server (MD_HOST, default <this host's IPv4 with dashes>.nip.io) serves the scenario documents.
# Containers carry the labels cimdlab=1 and cimdlab.root=<this checkout>; 'uninstall' removes only those, and kills
# only processes whose command line is this checkout's script and whose pid is in this lab's pidfiles.
#
# Options: ENGINE (podman|docker, auto), VERSIONS, RUNS (3), CHECKS ("01 … 10"), ATTEMPTS (3: a check that ends
#   "NOT RUN [vendor-fetch]" — a vendor document was not fetched — is tried again; every attempt is kept), MD_HOST, PORT_BASE (18100).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD; RT=$ROOT/lab/.runtime; mkdir -p "$RT"
. scripts/versions.env
VERSIONS=${VERSIONS:-$VERSIONS_DEFAULT}; RUNS=${RUNS:-3}; ATTEMPTS=${ATTEMPTS:-3}; PORT_BASE=${PORT_BASE:-18100}
CHECKS=${CHECKS:-"01 02 03 04 05 06 07 08 09 10"}
ADMIN_USER=lab-admin
if [ -z "${ENGINE:-}" ]; then
  if command -v podman >/dev/null; then ENGINE=podman; elif command -v docker >/dev/null; then ENGINE=docker
  else echo "no podman or docker: run scripts/platform.sh install" >&2; exit 1; fi
fi
export ENGINE
if [ -z "${MD_HOST:-}" ]; then
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  [ -n "$ip" ] || { echo "cannot determine this host's IPv4 address; set MD_HOST" >&2; exit 1; }
  MD_HOST="${ip//./-}.nip.io"
fi
MD="https://$MD_HOST:8443"
die(){ echo "lab: $*" >&2; exit 1; }
idx(){ local i=0 v; for v in $VERSIONS; do [ "$v" = "$1" ] && { echo $i; return; }; i=$((i+1)); done; die "unknown version $1"; }
ports(){ local b=$((PORT_BASE + $(idx "$1") * 10)); echo "$b $((b+1)) $((b+2))"; }   # stock ext noflag
digest(){ local k="KEYCLOAK_DIGEST_${1//./_}"; [ -n "${!k:-}" ] || die "no pinned digest for Keycloak $1 in versions.env"; echo "${!k}"; }

build(){
  for v in $VERSIONS; do
    local out=$RT/spi-$v t; mkdir -p "$out" "$RT/m2"; t=$(mktemp -d)
    cp -r spi/pom.xml spi/src "$t/"
    "$ENGINE" run --rm -v "$t:/src:Z" -v "$RT/m2:/root/.m2:Z" -w /src "$MAVEN_IMAGE" \
      mvn -B -q -DskipTests -Dkeycloak.version="$v" package
    cp "$t/target/cimd-fetch-parse-spi.jar" "$out/"; rm -rf "$t" 2>/dev/null || "$ENGINE" unshare rm -rf "$t" 2>/dev/null || true
    echo "built $out/cimd-fetch-parse-spi.jar ($(sha256sum "$out/cimd-fetch-parse-spi.jar" | cut -c1-12))"
  done
}

start_bg(){ # start_bg <pidfile> <log> <command...>
  local pf=$1 lg=$2; shift 2
  setsid nohup "$@" > "$lg" 2>&1 < /dev/null & echo $! > "$pf"; }
alive(){ [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
ours(){ # ours <pidfile> <script>: the pid is alive and runs this checkout's script (a reused pid is never killed)
  alive "$1" && grep -qxF "$ROOT/scripts/$2" <<<"$(tr '\0' '\n' < "/proc/$(cat "$1")/cmdline" 2>/dev/null)"; }
holds(){ # holds <pidfile> <script> <ip> <port>: ours, and it is the process listening on that address
  ours "$1" "$2" && grep -q "pid=$(cat "$1")," <<<"$(ss -ltnpH "( sport = :$4 )" 2>/dev/null | awk -v a="$3:$4" '$4==a')"; }
labeled(){ [ "$("$ENGINE" inspect --format '{{index .Config.Labels "cimdlab.root"}}' "$1" 2>/dev/null)" = "$ROOT" ]; }
# A Keycloak port is ours when this checkout's container for it is running with KC_HTTP_PORT=<port>: rootless
# containers hide the socket's pid from ss, and Keycloak exits when it cannot bind, so running = holding its port.
kc_holds(){ labeled "$1" && [ "$("$ENGINE" inspect --format '{{.State.Running}}' "$1" 2>/dev/null)" = true ] \
  && grep -qx "KC_HTTP_PORT=$2" <<<"$("$ENGINE" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2>/dev/null)"; }
need_ss(){ command -v ss >/dev/null || die "ss not found (iproute2): run scripts/platform.sh install"; }
# Never `producer | grep -q` here: under pipefail a producer killed by SIGPIPE (grep exits on the first match) fails
# the pipeline at random — and a negated test would then pass. Output is captured first, then matched.
addrs(){ ss -ltnH "( sport = :$1 )" 2>/dev/null | awk '{print $4}'; }   # addrs <port>: listening local addresses
listening(){ grep -qxF -e "$1:$2" -e "[::ffff:$1]:$2" <<<"$(addrs "$2")"; }   # listening <ip> <port>
except(){ # except <port> <allowed address...>: true when a listener on the port has an address not in the list
  local p=$1; shift; awk -v ok="$*" 'BEGIN{n=split(ok,a," "); for(i=1;i<=n;i++) A[a[i]]=1} NF && !($0 in A){f=1} END{exit !f}' <<<"$(addrs "$p")"; }
other_listener(){ except "$1" "127.0.0.2:$1"; }                                       # anything but our proxy address
foreign_listener(){ except "$1" "127.0.0.2:$1" "127.0.0.1:$1" "[::ffff:127.0.0.1]:$1"; }   # anything but proxy + Keycloak

kc_run(){ # kc_run <name> <version> <port> <kind>
  local name=$1 v=$2 port=$3 kind=$4 img; img="$KEYCLOAK_IMAGE@$(digest "$v")"
  if "$ENGINE" inspect "$name" >/dev/null 2>&1; then
    labeled "$name" || die "a container named $name exists that this checkout did not create — not touched"
    grep -qx "KC_HTTP_PORT=$port" <<<"$("$ENGINE" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$name")" \
      || die "$name exists on another port (PORT_BASE changed?): run 'scripts/lab.sh uninstall' with the old PORT_BASE first"
    "$ENGINE" start "$name" >/dev/null; return; fi
  local args=(-d --name "$name" --label cimdlab=1 --label "cimdlab.root=$ROOT" --network host -e KC_HTTP_PORT="$port" -e KC_HTTP_HOST=127.0.0.1
              --env-file "$RT/admin.env"
              -v "$RT/tls/ca.pem:/opt/keycloak/conf/truststores/md.pem:ro,Z")
  local cmd=(start-dev)
  case $kind in
    stock) cmd+=(--features=cimd);;
    noflag) ;;
    ext) [ -f "$RT/spi-$v/cimd-fetch-parse-spi.jar" ] || die "no extension jar for $v: run 'scripts/lab.sh build'"
         args+=(-v "$RT/spi-$v/cimd-fetch-parse-spi.jar:/opt/keycloak/providers/cimd-fetch-parse-spi.jar:ro,Z")
         cmd+=(--features=cimd --spi-client-policy-executor--client-id-metadata-document--cimd-provider-name=logging-cimd);;
  esac
  "$ENGINE" run "${args[@]}" "$img" "${cmd[@]}" >/dev/null
}

admin_secret(){ # a random bootstrap admin password per checkout (0600, never printed): a Keycloak that accepts it is ours
  [ -s "$RT/admin-password" ] && [ -s "$RT/admin.env" ] && return
  ( umask 077; openssl rand -hex 24 | tr -d '\n' > "$RT/admin-password"
    printf 'KC_BOOTSTRAP_ADMIN_USERNAME=%s\nKC_BOOTSTRAP_ADMIN_PASSWORD=%s\n' "$ADMIN_USER" "$(cat "$RT/admin-password")" > "$RT/admin.env" ); }
owned_once(){ # owned_once <version>: every listener of that version is held by this checkout's own container or process
  local p k c i=0; for p in $(ports "$1"); do k=$(echo stock ext noflag | cut -d' ' -f$((i+1))); i=$((i+1)); c=cimdlab-$k-$1
    listening 127.0.0.1 "$p" || { echo "127.0.0.1:$p: nothing listening" >&2; return 1; }
    kc_holds "$c" "$p" || { echo "127.0.0.1:$p: $c is not this checkout's running container for that port" >&2; return 1; }
    ! foreign_listener "$p" \
      || { echo "port $p: another listener besides the lab's" >&2; return 1; }
    holds "$RT/proxy-$p.pid" recording-proxy.py 127.0.0.2 "$p" || { echo "127.0.0.2:$p is not this lab's proxy" >&2; return 1; }
  done
  holds "$RT/metadata.pid" metadata-server.py 0.0.0.0 8443 || { echo "8443 is not this lab's metadata server" >&2; return 1; }; }
owned(){ # owned <version>: a negative answer is re-verified twice (3 s apart) — a probe (podman inspect, ss) can fail
  # for a moment under load; a lab that is really not ours stays not ours. Re-verifying sends nothing to the lab.
  local t; for t in 1 2 3; do owned_once "$1" && return 0; [ $t = 3 ] || sleep 3; done; return 1; }

preflight(){ # every port this lab needs must be free or held by this lab's own process: never take over another service
  need_ss
  local v p k i busy=; for v in $VERSIONS; do i=0; for p in $(ports "$v"); do k=$(echo stock ext noflag | cut -d' ' -f$((i+1))); i=$((i+1))
    if other_listener "$p"; then
      { kc_holds "cimdlab-$k-$v" "$p" && ! foreign_listener "$p"; } || busy+=" $p"; fi
    if listening 127.0.0.2 "$p"; then holds "$RT/proxy-$p.pid" recording-proxy.py 127.0.0.2 "$p" || busy+=" 127.0.0.2:$p"; fi
  done; done
  if [ -n "$(addrs 8443)" ] && ! holds "$RT/metadata.pid" metadata-server.py 0.0.0.0 8443; then busy+=" 8443"; fi
  [ -z "$busy" ] || die "port(s) in use by another service:$busy — set PORT_BASE (Keycloak ports) or free 8443"; }

install(){
  preflight
  if [ -z "$("$ENGINE" ps -a --filter "label=cimdlab.root=$ROOT" --format '{{.Names}}')" ]; then rm -f "$RT/admin.env" "$RT/admin-password"; fi
  admin_secret
  MD_HOST=$MD_HOST scripts/tls.sh
  mkdir -p "$RT/scenarios" "$RT/proxy"; touch "$RT/metadata-requests.jsonl"
  if ! ours "$RT/metadata.pid" metadata-server.py; then
    rm -f "$RT/metadata.pid"
    SCENARIOS=$RT/scenarios REQUEST_LOG=$RT/metadata-requests.jsonl MD_CERT=$RT/tls/chain.pem MD_KEY=$RT/tls/server.key \
      start_bg "$RT/metadata.pid" "$RT/metadata.log" python3 "$ROOT/scripts/metadata-server.py"
  fi
  for v in $VERSIONS; do
    read -r ps pe pn <<<"$(ports "$v")"
    kc_run "cimdlab-stock-$v" "$v" "$ps" stock; kc_run "cimdlab-ext-$v" "$v" "$pe" ext; kc_run "cimdlab-noflag-$v" "$v" "$pn" noflag
    for p in $ps $pe $pn; do
      ours "$RT/proxy-$p.pid" recording-proxy.py || RUN_LABEL_FILE=$RT/run-label start_bg "$RT/proxy-$p.pid" "$RT/proxy-$p.log" \
        python3 "$ROOT/scripts/recording-proxy.py" 127.0.0.2 "$p" 127.0.0.1 "$RT/proxy/$p.jsonl"
    done
  done
  echo "MD_HOST=$MD_HOST" > "$RT/env"
  local i; for i in $(seq 1 60); do status >/dev/null 2>&1 && { status; return 0; }; sleep 5; done
  status; die "lab not ready after 5 minutes"
}

status(){ # readiness gate: metadata server answers; every Keycloak answers through its proxy with the pinned version
  local ok=0 v p kind t got
  # ownership first: no request (and no admin secret) goes to a port this checkout does not hold at that moment
  for v in $VERSIONS; do owned "$v" 2>/dev/null || { echo "lab $v: not up, or not this checkout's own — not contacted"; return 1; }; done
  if curl -sk --fail --max-time 5 "$MD/_requests" 2>/dev/null | jq -e 'type=="array"' >/dev/null 2>&1; then echo "metadata  $MD  ready"; else echo "metadata  $MD  NOT READY"; ok=1; fi
  for v in $VERSIONS; do
    read -r ps pe pn <<<"$(ports "$v")"
    for kind in "stock $ps" "ext $pe" "noflag $pn"; do set -- $kind
      t=$(curl -s --max-time 8 -X POST "http://127.0.0.2:$2/realms/master/protocol/openid-connect/token" \
          --data-urlencode grant_type=password --data-urlencode client_id=admin-cli \
          --data-urlencode "username=$ADMIN_USER" --data-urlencode "password@$RT/admin-password" 2>/dev/null | jq -r '.access_token // empty' 2>/dev/null) || t=
      got=; [ -n "$t" ] && got=$(curl -s --max-time 8 "http://127.0.0.2:$2/admin/serverinfo" -H "@"<(printf 'Authorization: Bearer %s\n' "$t") | jq -r '.systemInfo.version // empty')
      if [ "$got" = "$v" ]; then echo "cimdlab-$1-$v  127.0.0.2:$2  ready"; else echo "cimdlab-$1-$v  127.0.0.2:$2  NOT READY ${got:+($got)}"; ok=1; fi
    done
  done
  return $ok
}

uninstall(){
  need_ss
  local f; for f in "$RT"/proxy-*.pid; do ours "$f" recording-proxy.py && kill "$(cat "$f")" 2>/dev/null; rm -f "$f"; done
  f=$RT/metadata.pid; ours "$f" metadata-server.py && kill "$(cat "$f")" 2>/dev/null; rm -f "$f"; sleep 1
  local names; names=$("$ENGINE" ps -a --filter label=cimdlab=1 --filter "label=cimdlab.root=$ROOT" --format '{{.Names}}')
  [ -z "$names" ] || "$ENGINE" rm -f $names >/dev/null
  [ -z "$("$ENGINE" ps -a --filter label=cimdlab=1 --filter "label=cimdlab.root=$ROOT" --format '{{.Names}}')" ] || die "lab containers left"
  local v p left=; for v in $VERSIONS; do for p in $(ports "$v"); do [ -n "$(addrs "$p")" ] && left+=" $p"; done; done
  [ -z "$left" ] || die "lab ports still in use:$left (another service, or a lab process this script did not start)"
  rm -f "$RT/admin.env" "$RT/admin-password"
  echo "lab removed (containers labelled cimdlab=1, proxies, metadata server)"
}

test_(){
  status >/dev/null || { status; die "lab not ready — no test run (a dead lab reports NOT RUN as if it were a result)"; }
  local session; session=$(date -u +%Y%m%dT%H%M%SZ); local plan=$RT/plan-$session.tsv runs=$RT/runs
  mkdir -p "$runs" results
  printf 'session\tversion\tcheck\trun\n' > "$plan"
  local r v c; for r in $(seq 1 "$RUNS"); do for v in $VERSIONS; do for c in $CHECKS; do printf '%s\t%s\t%s\t%s\n' "$session" "$v" "$c" "$r" >> "$plan"; done; done; done
  echo "$session" > "$RT/last-session"
  echo "plan: $(($(wc -l < "$plan") - 1)) runs (versions: $VERSIONS · checks: $CHECKS · RUNS=$RUNS), session $session"
  for r in $(seq 1 "$RUNS"); do for v in $VERSIONS; do
    read -r ps pe pn <<<"$(ports "$v")"
    for c in $CHECKS; do
      local f a rc id d; f=$(ls checks/"$c"-*.sh); a=0
      while :; do a=$((a+1))
        owned "$v" || die "lab $v is not (or no longer) this checkout's own — no check sends traffic to it"
        id="$session-v$v-c$c-r$r-a$a"; d=$runs/$id; mkdir -p "$d"
        echo "$id" > "$RT/run-label"
        local t0 t0s m0; t0=$(date -u +%FT%H:%M:%S.%NZ); t0s=$(date -u +%FT%H:%M:%SZ); m0=$(wc -l < "$RT/metadata-requests.jsonl" 2>/dev/null || echo 0)
        rc=0; : > "$d/observed.jsonl"
        env OBS_FILE="$d/observed.jsonl" ADMIN_USER="$ADMIN_USER" ADMIN_PASSWORD_FILE="$RT/admin-password" RUN_ID="$id" CHECK="$(basename "$f" .sh)" RESULTS="$ROOT/results/measurements.tsv" MD="$MD" SCENARIOS="$RT/scenarios" \
            KC_STOCK="http://127.0.0.2:$ps" C_STOCK="cimdlab-stock-$v" KC_EXT="http://127.0.0.2:$pe" C_EXT="cimdlab-ext-$v" \
            KC_NOFLAG="http://127.0.0.2:$pn" C_NOFLAG="cimdlab-noflag-$v" bash "$f" > "$d/stdout.txt" 2>&1 || rc=$?
        sleep 1; : > "$RT/run-label"
        # checked again after the attempt: an attempt whose lab changed owner meanwhile is never a result (summary.py).
        # Between the two checks the lab assumes no other process takes its ports; that window is not excluded.
        local oa=true; owned "$v" 2>/dev/null || oa=false
        cat "$RT"/proxy/*.jsonl 2>/dev/null | jq -c --arg id "$id" 'select(.run==$id)' > "$d/requests.jsonl"
        tail -n +"$((m0+1))" "$RT/metadata-requests.jsonl" 2>/dev/null > "$d/metadata-requests.jsonl" || true
        for k in stock ext noflag; do "$ENGINE" logs --since "$t0s" "cimdlab-$k-$v" > "$d/server-$k.log" 2>&1 || true; done
        jq -n --arg id "$id" --arg session "$session" --arg v "$v" --arg c "$c" --argjson r "$r" --argjson a "$a" --argjson rc "$rc" --argjson oa "$oa" \
          --arg t0 "$t0" --arg t1 "$(date -u +%FT%H:%M:%S.%NZ)" --arg sha "$(sha256sum "$f" | cut -c1-64)" \
          --arg jar "$(sha256sum "$RT/spi-$v/cimd-fetch-parse-spi.jar" 2>/dev/null | cut -c1-64)" --arg img "$(digest "$v")" \
          '{run_id:$id, session:$session, version:$v, check:$c, run:$r, attempt:$a, exit:$rc, owned_after:$oa, start:$t0, end:$t1,
            check_sha256:$sha, extension_jar_sha256:$jar, keycloak_digest:$img}' > "$d/manifest.json"
        printf '%-48s exit %s  %s\n' "$id" "$rc" "$(grep -E '^(PASS|FAIL|NOT RUN)' "$d/stdout.txt" | tail -1 | cut -c1-90)"
        # a NOT RUN caused by a vendor fetch that did not complete is retried; every attempt stays on disk
        if [ "$rc" = 77 ] && grep -q '^NOT RUN \[vendor-fetch\]' "$d/stdout.txt" && [ "$a" -lt "$ATTEMPTS" ]; then continue; fi
        break
      done
    done
  done; done
  summary
}

summary(){ python3 scripts/summary.py "$(cat "$RT/last-session")"; }

case "${1:-status}" in
  build) build;; install) install;; uninstall) uninstall;; reinstall) uninstall; install;; status) status;;
  test) test_;; summary) summary;; all) build; install; test_;;
  *) echo "usage: $0 build|install|uninstall|reinstall|status|test|summary|all" >&2; exit 2;;
esac
