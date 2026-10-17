#!/usr/bin/env bash
# Act 3: one fetch-and-parse override (lenient-cimd). The eight published identities with anonymous registration
# locked (checks/05, 06), then two positive and five negative controls (checks/04).
. "$(dirname "$0")/lib.sh"
KC=$KC_EXT; REALM=demo-executor; refresh

title "Act 3 · Keycloak $(server_version) · executor lenient-cimd (overrides the one method that fetches and parses)"

fetch_vendor_docs
HOSTS="$(all_vendor_hosts) [::1]"
realm_setup $REALM "$(json_array $HOSTS)" lenient-cimd
note "allowlist as in act 1, plus [::1] (goose also lists an IPv6 loopback redirect)"

step "Lock anonymous dynamic registration in the same realm, then try it"
set_trusted_hosts $REALM "[]"; anon_register $REALM
printf '  anonymous registration → HTTP %s  %s%s%s\n' "$DS" "$D" "$DP" "$N"
printf '  CIMD clients in the realm: %s\n' "$(cimd_say $REALM)"

step "The same eight published identities"
ACC=0
for n in "${ORDER[@]}"; do
  auth $REALM "$(cid_of $n)" "$(ru_of $n)" $C_EXT
  [ "$(outcome)" = accepted ] && ACC=$((ACC+1))
  printf '  %-20s HTTP %s  %b  %s%s%s\n' "${NAME[$n]}" "$H" "$(verdict)" "$D" "$(reason)" "$N"
done
printf '  %s%d of 8 accepted%s · CIMD clients in the realm now: %s\n' "$B" "$ACC" "$N" "$(cimd_say $REALM)"

step "Two positive and five negative controls through the same executor (local metadata server)"
curl -sk -o /dev/null --max-time 5 "$MD/_requests" || not_run "metadata server not reachable"
tmpl(){ jq -nc --arg u "$MD/c/$1.json" --arg r "$MD/p/redirect" \
  '{client_id:$u, client_name:"demo", redirect_uris:[$r], token_endpoint_auth_method:"none", grant_types:["authorization_code"], response_types:["code"]}'; }
put(){ printf '%s' "$2" > "$SCENARIOS/$1.json"; }
put demo-clean   "$(tmpl demo-clean)"
put demo-unknown "$(tmpl demo-unknown | jq -c '. + {token_endpoint_auth_methods_supported:["none"]}')"
put demo-badjson '{"client_id": "this is not valid JSON'
put demo-noid    "$(tmpl demo-noid | jq -c 'del(.client_id)')"
put demo-otherid "$(tmpl demo-otherid | jq -c --arg o "$MD/c/other.json" '.client_id=$o')"
put demo-typo    "$(tmpl demo-typo | jq -c --arg r "$MD/p/redirect" 'del(.redirect_uris) + {redirect_uri:$r}')"
put demo-foreign "$(tmpl demo-foreign | jq -c '. + {logo_uri:"https://other-domain.example/logo.png"}')"
realm_setup demo-controls "[\"$(md_host)\"]" lenient-cimd
for c in "demo-clean|clean document" "demo-unknown|+ one unknown property" "demo-badjson|malformed JSON" \
         "demo-noid|missing client_id" "demo-otherid|client_id != its URL" "demo-typo|redirect_uris typo" \
         "demo-foreign|foreign-domain logo_uri"; do
  auth demo-controls "$MD/c/${c%%|*}.json" "$MD/p/redirect" $C_EXT
  printf '  %-24s HTTP %s  %b  %s%s%s\n' "${c#*|}" "$H" "$(verdict)" "$D" "$(reason)" "$N"
done

step "Reading"
note "Unknown properties are tolerated; the inherited validation still refuses the five controls."
note "The repository's checks cover 26.7.0 and 26.8.0 (results/ and evidence/)."
wait_key
