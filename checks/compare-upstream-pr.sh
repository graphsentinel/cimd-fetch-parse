#!/usr/bin/env bash
# compare-upstream-pr.sh: the same documents against three servers, side by side (not one of the numbered checks).
#   stock    the lab's stock Keycloak, stock executor                  (KC_STOCK / C_STOCK)
#   lenient  the lab's ext Keycloak, this repository's lenient-cimd   (KC_EXT / C_EXT)
#   pr       Keycloak with an upstream change applied, stock executor  (KC_PR / C_PR, e.g. 26.8.0 + keycloak PR #51235)
# Rows: the eight published documents (anonymous registration locked), the seven controls of check 04, the three cases
# of check 11, and edge documents where two lenient parsers could still differ. Each cell: outcome, the server's reason
# (log) and the message shown to the caller. Output: a TSV on stdout, one row per document and server.
#   KC_PR=http://127.0.0.2:18103 C_PR=cimdlab-pr51235-26.8.0 checks/compare-upstream-pr.sh   (inside the lab env)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
: "${KC_PR:?KC_PR (base URL of the server with the upstream change)}" "${C_PR:?C_PR (its container)}"
WAIT=${CACHE_WAIT:-305}
SERVERS="stock|$KC_STOCK|$C_STOCK|client-id-metadata-document lenient|$KC_EXT|$C_EXT|lenient-cimd pr|$KC_PR|$C_PR|client-id-metadata-document"
curl -sk -o /dev/null --max-time 5 "$MD/_requests" || not_run "metadata server not reachable"
tmpl(){ jq -nc --arg u "$MD/c/$1.json" --arg r "$MD/p/redirect" \
  '{client_id:$u, client_name:"lab", redirect_uris:[$r], token_endpoint_auth_method:"none", grant_types:["authorization_code"], response_types:["code"]}'; }
put(){ printf '%s' "$2" > "$SCENARIOS/$1.json"; rm -f "$SCENARIOS/$1.status" "$SCENARIOS/$1.headers.json"; }
fetches(){ curl -sk --max-time 10 "$MD/_requests" | jq --arg p "/c/$1.json" '[.[]|select(.path==$p)]|length'; }
client_of(){ clients_json "$1" | jq -c --arg c "$2" '[.[]|select(.clientId==$c)|{public:.publicClient, auth:.clientAuthenticatorType}]|first // {}'; }
row(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$(outcome)" "$H" "$CAUSE" "${MSG:--}"; }

# documents per server (each server gets its own copies, so caches and persisted clients never mix)
docs_for(){ local s=$1 p=cmp-$1
  put $p-clean   "$(tmpl $p-clean)"
  put $p-unknown "$(tmpl $p-unknown | jq -c '. + {token_endpoint_auth_methods_supported:["none"]}')"
  put $p-badjson '{"client_id": "this is not valid JSON'
  put $p-noid    "$(tmpl $p-noid | jq -c 'del(.client_id)')"
  put $p-otherid "$(tmpl $p-otherid | jq -c --arg o "$MD/c/other.json" '.client_id=$o')"
  put $p-typo    "$(tmpl $p-typo | jq -c --arg r "$MD/p/redirect" 'del(.redirect_uris) + {redirect_uri:$r}')"
  put $p-foreign "$(tmpl $p-foreign | jq -c '. + {logo_uri:"https://other-domain.example/logo.png"}')"
  # edge documents: shapes where two lenient parsers could still differ
  put $p-redirstr   "$(tmpl $p-redirstr | jq -c --arg r "$MD/p/redirect" '.redirect_uris=$r')"
  put $p-nullunk    "$(tmpl $p-nullunk | jq -c '. + {x_unknown:null}')"
  put $p-nested     "$(tmpl $p-nested | jq -c '. + {x_vendor:{a:{b:{c:[1,{d:true}]}}}}')"
  put $p-dupkey     "$(tmpl $p-dupkey | sed -E 's/^\{/{"client_name":"first",/')"
  put $p-empty      ''
  put $p-array      "[$(tmpl $p-array)]"
  put $p-unknownbig "$(tmpl $p-unknownbig | jq -c --arg pad "$(head -c 4600 /dev/zero | tr '\0' 'x')" '. + {x_padding:$pad}')"
  put $p-unknownover "$(tmpl $p-unknownover | jq -c --arg pad "$(head -c 5200 /dev/zero | tr '\0' 'x')" '. + {x_padding:$pad}')"
  put $p-cache  "$(tmpl $p-cache)"; printf '{"Cache-Control":"max-age=3600"}' > "$SCENARIOS/$p-cache.headers.json"
  put $p-noauth "$(tmpl $p-noauth | jq -c 'del(.token_endpoint_auth_method)')"
  put $p-304    "$(tmpl $p-304)"; }

printf 'document\tserver\toutcome\thttp\tserver_reason\tcaller_message\n'
for sv in $SERVERS; do IFS='|' read -r s KC c ex <<<"$sv"; refresh
  docs_for $s; p=cmp-$s
  # 1. the eight published documents, anonymous registration locked
  fetch_vendor_docs; realm_setup cmp-vendor-$s "$(json_array $(all_vendor_hosts) '[::1]')" $ex
  set_trusted_hosts cmp-vendor-$s "[]"; anon_register cmp-vendor-$s
  printf 'anonymous-registration\t%s\t%s\t%s\t%s\t%s\n' $s "$([ "$DS" = 403 ] && echo refused || echo "NOT LOCKED")" "$DS" "$DP" -
  for d in "${VENDOR_DOCS[@]}"; do n=${d%%|*}; auth cmp-vendor-$s "$(cid_of $n)" "$(ru_of $n)" $c; row "$n" $s; done
  # 2. controls and edge documents
  realm_setup cmp-local-$s "[\"$(md_host)\"]" $ex
  for n in clean unknown badjson noid otherid typo foreign redirstr nullunk nested dupkey empty array unknownbig unknownover; do
    auth cmp-local-$s "$MD/c/$p-$n.json" "$MD/p/redirect" $c; row "$n" $s
    [ "$n" != dupkey ] || printf 'dupkey-stored-name\t%s\t%s\t-\t-\t-\n' $s "$(clients_json cmp-local-$s | jq -r --arg c "$MD/c/$p-dupkey.json" '[.[]|select(.clientId==$c)|.name]|first // "-"')"
  done
  # 3. the check 11 cases
  f0=$(fetches $p-cache); auth cmp-local-$s "$MD/c/$p-cache.json" "$MD/p/redirect" $c; auth cmp-local-$s "$MD/c/$p-cache.json" "$MD/p/redirect" $c
  printf 'cache-two-requests\t%s\t%s\t-\t-\tfetches=%s\n' $s "$(outcome)" "$(( $(fetches $p-cache) - f0 ))"
  auth cmp-local-$s "$MD/c/$p-noauth.json" "$MD/p/redirect" $c
  printf 'noauth-client\t%s\t%s\t%s\t-\t%s\n' $s "$(outcome)" "$H" "$(client_of cmp-local-$s "$MD/c/$p-noauth.json")"
  auth cmp-local-$s "$MD/c/$p-304.json" "$MD/p/redirect" $c; echo 304 > "$SCENARIOS/$p-304.status"
done
sleep "$WAIT"
for sv in $SERVERS; do IFS='|' read -r s KC c ex <<<"$sv"; refresh; p=cmp-$s
  auth cmp-local-$s "$MD/c/$p-304.json" "$MD/p/redirect" $c; row 304-on-refresh $s; rm -f "$SCENARIOS/$p-304.status"
done
