#!/usr/bin/env bash
# 10 · With the lenient-cimd executor, are all eight accepted and persisted in one run, with anonymous
#      registration refused in the same realm?
#
# One realm: allowlist = IPv4/name hosts + "[::1]" (check 09); anonymous DCR locked and verified refused by the
# Trusted Hosts policy (HTTP 403) before the eight requests; CIMD client rows read before and after; the final
# set of client_ids must equal the eight requested ones. A document Keycloak could not fetch (that request's own
# server log) makes 8/8 untestable in this run: NOT RUN, unless something already contradicts the claim.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT; REALM=lab-eight
refresh
fetch_vendor_docs
HOSTS="$(all_vendor_hosts) [::1]"
realm_setup $REALM "$(json_array $HOSTS)" lenient-cimd
set_trusted_hosts $REALM '[]'
anon_register $REALM; DCR=$DS; POL=$DP
echo "anonymous registration: HTTP $DCR $POL"
case "$DCR" in 2??|3??|5??) fail "anonymous registration answered $DCR, not refused";; esac
{ [ "$DCR" = 403 ] && [ "$POL" = "Policy 'Trusted Hosts'" ]; } || not_run "anonymous registration not refused by Trusted Hosts ($DCR $POL) — the lock is not shown"
BEFORE=$(cimd_count $REALM) || not_run "could not count clients"
[ "$BEFORE" = 0 ] || not_run "the realm did not start empty ($BEFORE)"
ACCEPTED=0; declare -A GOT
for d in "${VENDOR_DOCS[@]}"; do n=${d%%|*}
  auth $REALM "$(cid_of $n)" "$(ru_of $n)" $C_EXT; expect $n accepted
  [ "$(outcome)" = accepted ] && { ACCEPTED=$((ACCEPTED+1)); GOT[$n]=1; }
  printf '  %-15s HTTP %s  %s\n' "$n" "$H" "$CAUSE"; record "status:$n" "$H"
done
AFTER=$(cimd_count $REALM) || not_run "could not count clients"
HAVE=$(cimd_ids $REALM) || not_run "could not list clients"
WANT=$(for d in "${VENDOR_DOCS[@]}"; do cid_of ${d%%|*}; done | LC_ALL=C sort | paste -sd, -)
SAME=no; [ "$HAVE" = "$WANT" ] && SAME=yes
for n in "${!GOT[@]}"; do [[ ",$HAVE," == *",$(cid_of $n),"* ]] || BAD+=("$n accepted but not persisted"); done
for c in ${HAVE//,/ }; do [[ ",$WANT," == *",$c,"* ]] || BAD+=("unexpected persisted client $c"); done
echo "accepted=$ACCEPTED · CIMD client rows $BEFORE -> $AFTER · final client_ids = the eight requested: $SAME"
record dcr "$DCR" accepted $ACCEPTED rows_before $BEFORE rows_after $AFTER same_client_ids $SAME not_fetched ${#NETS[@]}
settle
{ [ "$AFTER" = 8 ] && [ "$SAME" = yes ]; } || fail "persisted clients are not exactly the eight ($AFTER rows)"
echo "PASS: all eight accepted and persisted in one run, with anonymous registration refused (403, Trusted Hosts)."
