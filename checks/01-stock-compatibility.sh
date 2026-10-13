#!/usr/bin/env bash
# 01 · Which of eight published CIMD client identities does stock Keycloak accept, and why are the rest refused?
#
# Stock Keycloak (--features=cimd), a realm with the CIMD client policy whose allowlist holds the host of every
# *uri property in the eight documents, so the only variable is the document content. Every refusal is classified
# from the server log of that request: a parse refusal is a result; a refusal for any other reason is a FAIL; a
# document Keycloak could not fetch makes the check NOT RUN (unless something already contradicts the claim).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_STOCK; REALM=lab-stock-compat
refresh
fetch_vendor_docs
HOSTS=$(all_vendor_hosts)
realm_setup $REALM "$(json_array $HOSTS)"
echo "allowlist: $(printf '%s ' $HOSTS)"
ACCEPTED=0; PARSE=0
for d in "${VENDOR_DOCS[@]}"; do n=${d%%|*}
  auth $REALM "$(cid_of $n)" "$(ru_of $n)" $C_STOCK
  expect "$n" parse-or-accepted
  case "$(outcome)" in accepted) ACCEPTED=$((ACCEPTED+1));; refused) [[ $CAUSE == PARSE:* ]] && PARSE=$((PARSE+1));; esac
  printf '  %-15s HTTP %s  %s  %s\n' "$n" "$H" "$(outcome)" "$CAUSE"
  record "status:$n" "$H" "cause:$n" "$CAUSE" "message:$n" "${MSG:--}"
done
record accepted $ACCEPTED refused_parse $PARSE
settle
{ [ "$PARSE" -ge 1 ] && [ "$ACCEPTED" -ge 1 ]; } || fail "parse refusals=$PARSE accepted=$ACCEPTED"
echo "PASS: $PARSE of 8 refused by stock Keycloak $(server_version) at parse time, $ACCEPTED accepted."
