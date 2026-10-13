#!/usr/bin/env bash
# 08 · "Lock anonymous registration, keep only CIMD": how many of the eight get in, stock vs lenient-cimd?
#
# Two realms on the extension server with the same allowlist (IPv4 and name hosts), anonymous DCR locked and
# verified refused in each. A refusal must be a parse refusal or an allowlist-host refusal; anything else is a FAIL.
# Not measured: whether publishers would change their documents for such a posture.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT
refresh
fetch_vendor_docs
HOSTS=$(all_vendor_hosts)
pass(){ # pass <realm> <executor>: sets ACC, REF
  local r=$1 ex=$2 n; ACC=0; REF=0
  realm_setup $r "$(json_array $HOSTS)" $ex
  set_trusted_hosts $r '[]'
  anon_register $r
  case "$DS" in 403) ;; 000|4??) not_run "$r: anonymous registration not refused with 403 ($DS) — the lock is not shown";; *) BAD+=("$r: anonymous registration answered $DS");; esac
  echo "  $r: anonymous registration HTTP $DS ($DP)"
  for n in "${!DOC[@]}"; do
    auth $r "$(cid_of $n)" "$(ru_of $n)" $C_EXT
    case "$(outcome)" in
      accepted) ACC=$((ACC+1));;
      refused) REF=$((REF+1)); [[ $CAUSE == PARSE:* || $CAUSE == DOMAIN:* ]] || BAD+=("$r $n: refused for another reason ($CAUSE)");;
      *) expect "$r $n" accepted;;   # network -> NETS, error -> BAD
    esac
  done; }
pass lab-cimd-only-stock client-id-metadata-document; SA=$ACC; SR=$REF
pass lab-cimd-only-lenient lenient-cimd; LA=$ACC; LR=$REF
echo "  stock executor:   $SA accepted / $SR refused"
echo "  lenient-cimd:     $LA accepted / $LR refused"
record stock_accepted $SA stock_refused $SR lenient_accepted $LA lenient_refused $LR
settle
[ "$SA" -ge 1 ] || fail "positive control: nothing accepted with the stock executor"
[ "$LA" -gt "$SA" ] || fail "lenient-cimd is not better than stock ($LA vs $SA)"
echo "PASS: CIMD only: stock $SA/8, lenient-cimd $LA/8."
