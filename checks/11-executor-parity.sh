#!/usr/bin/env bash
# 11 · Does lenient-cimd behave like the stock executor everywhere except unknown properties?
#
# Same Keycloak (ext container: both executors installed), two realms, one per executor, the same documents from the
# local metadata server. Clean documents only, so the stock parser accepts them too; any difference is the override's.
#   cache   document sent with Cache-Control: max-age=3600, two authorization requests: how many fetches?
#   noauth  document without token_endpoint_auth_method: accepted, and persisted as a public client?
#   304     after the cached copy expired (wait CACHE_WAIT s, longer than the default 300 s minimum cache time), the
#           metadata server answers 304 Not Modified: is the authorization request still accepted?
# PASS when lenient-cimd gives the same result as the stock executor in all three.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT; WAIT=${CACHE_WAIT:-305}
refresh
curl -sk -o /dev/null --max-time 5 "$MD/_requests" || not_run "metadata server not reachable"
tmpl(){ jq -nc --arg u "$MD/c/$1.json" --arg r "$MD/p/redirect" \
  '{client_id:$u, client_name:"lab", redirect_uris:[$r], token_endpoint_auth_method:"none", grant_types:["authorization_code"], response_types:["code"]}'; }
put(){ printf '%s' "$2" > "$SCENARIOS/$1.json"; rm -f "$SCENARIOS/$1.status" "$SCENARIOS/$1.headers.json"; }
fetches(){ curl -sk --max-time 10 "$MD/_requests" | jq --arg p "/c/$1.json" '[.[]|select(.path==$p)]|length'; }
client_of(){ clients_json "$1" | jq -c --arg c "$MD/c/$2.json" '[.[]|select(.clientId==$c)|{public:.publicClient, auth:.clientAuthenticatorType}]|first // {}'; }

declare -A R
EXS="client-id-metadata-document lenient-cimd"
for ex in $EXS; do s=${ex%%-*}   # client | lenient
  realm=lab-parity-$s
  put par-cache-$s "$(tmpl par-cache-$s)"; printf '{"Cache-Control":"max-age=3600"}' > "$SCENARIOS/par-cache-$s.headers.json"
  put par-noauth-$s "$(tmpl par-noauth-$s | jq -c 'del(.token_endpoint_auth_method)')"
  put par-304-$s "$(tmpl par-304-$s)"
  realm_setup $realm "[\"$(md_host)\"]" $ex
  f0=$(fetches par-cache-$s)
  auth $realm "$MD/c/par-cache-$s.json" "$MD/p/redirect" $C_EXT; a1=$(outcome)
  auth $realm "$MD/c/par-cache-$s.json" "$MD/p/redirect" $C_EXT; a2=$(outcome)
  R[cache:$s]="$a1,$a2,fetches=$(( $(fetches par-cache-$s) - f0 ))"
  auth $realm "$MD/c/par-noauth-$s.json" "$MD/p/redirect" $C_EXT
  R[noauth:$s]="$(outcome),$(client_of $realm par-noauth-$s)"
  auth $realm "$MD/c/par-304-$s.json" "$MD/p/redirect" $C_EXT; R[304a:$s]=$(outcome)
  echo 304 > "$SCENARIOS/par-304-$s.status"
done
echo "  waiting ${WAIT}s for the cached copies to expire"; sleep "$WAIT"
for ex in $EXS; do s=${ex%%-*}; refresh
  f0=$(fetches par-304-$s)
  auth lab-parity-$s "$MD/c/par-304-$s.json" "$MD/p/redirect" $C_EXT
  R[304:$s]="${R[304a:$s]},then $(outcome) HTTP $H ${CAUSE},fetches=$(( $(fetches par-304-$s) - f0 ))"
  rm -f "$SCENARIOS/par-304-$s.status"
done

printf '  %-7s %-58s %s\n' case "stock executor" "lenient-cimd"
for k in cache noauth 304; do
  printf '  %-7s %-58s %s\n' $k "${R[$k:client]}" "${R[$k:lenient]}"
  record "stock:$k" "${R[$k:client]}" "lenient:$k" "${R[$k:lenient]}"
  [ "${R[$k:client]}" = "${R[$k:lenient]}" ] || BAD+=("$k: stock '${R[$k:client]}' vs lenient-cimd '${R[$k:lenient]}'")
done
settle
echo "PASS: lenient-cimd caches, defaults the auth method and handles 304 like the stock executor."
