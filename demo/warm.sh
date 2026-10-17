#!/usr/bin/env bash
# Warm-up before a live run: one authorization request per published document to a separate realm (demo-warm) on
# stock and ext, so the first fetch of each URL (Keycloak's cold HTTP client can time out) is not part of an act.
# Nothing here is shown as a result.
PAUSE=0 PRESENT=0 . "$(dirname "$0")/lib.sh"
fetch_vendor_docs; HOSTS="$(all_vendor_hosts) [::1]"
for k in "$KC_STOCK $C_STOCK" "$KC_EXT $C_EXT"; do set -- $k; KC=$1; refresh
  realm_setup demo-warm "$(json_array $HOSTS)" >/dev/null
  for n in "${ORDER[@]}"; do auth demo-warm "$(cid_of $n)" "$(ru_of $n)" $2; done
  printf 'warm %s\n' "$2"; done
