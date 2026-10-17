#!/usr/bin/env bash
# Act 1: stock Keycloak meets the eight published CIMD client identities (same request as checks/01).
. "$(dirname "$0")/lib.sh"
KC=$KC_STOCK; REALM=demo-stock; refresh

title "Act 1 · Stock Keycloak $(server_version) (--features=cimd) · eight published MCP client identities"

step "Fetch the eight documents their vendors publish (client_id = the document's own URL)"
fetch_vendor_docs
for n in "${ORDER[@]}"; do printf '  %-20s %s\n' "${NAME[$n]}" "$(short "$(cid_of $n)")"; done

step "Realm with the stock CIMD policy; allowlist = hosts of every *uri property in the documents"
HOSTS=$(all_vendor_hosts); realm_setup $REALM "$(json_array $HOSTS)"
note "$(wc -w <<<"$HOSTS") hosts allowed"

step "Authorization request with each identity: what the caller sees, and why (server log)"
REF=0; ACC=0; NET=0
for n in "${ORDER[@]}"; do
  auth $REALM "$(cid_of $n)" "$(ru_of $n)" $C_STOCK
  case "$(outcome)" in accepted) ACC=$((ACC+1));; refused) REF=$((REF+1));; *) NET=$((NET+1));; esac
  printf '  %-20s HTTP %s  %b  %s%s%s\n' "${NAME[$n]}" "$H" "$(verdict)" "$D" "${MSG:+caller: \"$MSG\"  }$( [ "$CAUSE" = - ] || printf 'server: %s' "$(reason)")" "$N"
done

step "Result"
printf '  %s%d of 8 refused%s, %d accepted.\n' "$B" "$REF" "$N" "$ACC"
[ "$NET" -eq 0 ] || printf '  %s%d request(s) not completed (network or error): not a result; run again.%s\n' "$R" "$NET" "$N"
note "The caller is told the fetch failed. The server log says the document arrived and its parse failed"
note "on a property Keycloak does not know."
note "(Background, not measured here: RFC 7591 §2, unknown client metadata MUST be ignored.)"
wait_key
