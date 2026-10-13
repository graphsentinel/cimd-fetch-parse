#!/usr/bin/env bash
# 05 · Does the lenient-cimd executor remove every parse refusal on the eight real documents?
#
# Same allowlist as check 01 (IPv4 and name hosts only), executor lenient-cimd. Expected: no parse refusal left.
# goose also lists an IPv6 loopback redirect that this allowlist does not contain, so goose is refused for that host
# (DOMAIN:[::1], see check 09); any other refusal, of goose or of another document, is a FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT; REALM=lab-extension-real
refresh
fetch_vendor_docs
HOSTS=$(all_vendor_hosts)
realm_setup $REALM "$(json_array $HOSTS)" lenient-cimd
ACCEPTED=0; DOMAIN=0
for d in "${VENDOR_DOCS[@]}"; do n=${d%%|*}
  auth $REALM "$(cid_of $n)" "$(ru_of $n)" $C_EXT
  if [ $n = goose ]; then expect $n 'cause:DOMAIN:[::1]'; [ "$CAUSE" = 'DOMAIN:[::1]' ] && DOMAIN=$((DOMAIN+1)); else expect $n accepted; fi
  [ "$(outcome)" = accepted ] && ACCEPTED=$((ACCEPTED+1))
  printf '  %-15s HTTP %s  %s\n' "$n" "$H" "$CAUSE"; record "status:$n" "$H" "cause:$n" "$CAUSE"
done
record accepted $ACCEPTED refused_domain $DOMAIN
settle
[ "$ACCEPTED" -ge 1 ] || fail "nothing accepted"
echo "PASS: no parse refusal left ($ACCEPTED accepted, $DOMAIN refused for an allowlist host)."
