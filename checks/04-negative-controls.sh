#!/usr/bin/env bash
# 04 · Does tolerating unknown properties loosen anything else? Two positive and five negative controls.
#
# Keycloak with this repository's lenient-cimd executor (one fetch-and-parse override). Documents served by the local
# metadata server. Each negative control must stay refused, and for its own reason (server log of that request).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT; REALM=lab-controls
refresh
curl -sk -o /dev/null --max-time 5 "$MD/_requests" || not_run "metadata server not reachable"
tmpl(){ jq -nc --arg u "$MD/c/$1.json" --arg r "$MD/p/redirect" \
  '{client_id:$u, client_name:"lab", redirect_uris:[$r], token_endpoint_auth_method:"none", grant_types:["authorization_code"], response_types:["code"]}'; }
put(){ printf '%s' "$2" > "$SCENARIOS/$1.json"; }
put ctl-clean   "$(tmpl ctl-clean)"
put ctl-unknown "$(tmpl ctl-unknown | jq -c '. + {token_endpoint_auth_methods_supported:["none"]}')"
put ctl-badjson '{"client_id": "this is not valid JSON'
put ctl-noid    "$(tmpl ctl-noid | jq -c 'del(.client_id)')"
put ctl-otherid "$(tmpl ctl-otherid | jq -c --arg o "$MD/c/other.json" '.client_id=$o')"
put ctl-typo    "$(tmpl ctl-typo | jq -c --arg r "$MD/p/redirect" 'del(.redirect_uris) + {redirect_uri:$r}')"
put ctl-foreign "$(tmpl ctl-foreign | jq -c '. + {logo_uri:"https://other-domain.example/logo.png"}')"
realm_setup $REALM "[\"$(md_host)\"]" lenient-cimd
for e in "ctl-clean|accepted" "ctl-unknown|accepted" "ctl-badjson|cause:MALFORMED_JSON" "ctl-noid|cause:CLIENT_ID_MISSING" \
         "ctl-otherid|cause:CLIENT_ID_MISMATCH" "ctl-typo|cause:REDIRECT_MISMATCH" "ctl-foreign|cause:DOMAIN:other-domain.example"; do n=${e%%|*}
  auth $REALM "$MD/c/$n.json" "$MD/p/redirect" $C_EXT
  expect "$n" "${e#*|}"
  printf '  %-12s HTTP %s  %-8s %s\n' "$n" "$H" "$(outcome)" "$CAUSE"
  record "result:$n" "$(outcome)" "cause:$n" "$CAUSE"
done
settle
echo "PASS: the unknown property is accepted; malformed JSON, missing client_id, mismatched client_id, redirect_uris typo and a foreign-domain URI are each refused for their own reason."
