#!/usr/bin/env bash
# 06 · Does an agent whose document is refused have another automatic way in? (default realm settings)
#
# Door 1: CIMD with the refused published document. Door 2: anonymous dynamic client registration, with the
# realm's default registration policies untouched. Positive control: an accepted document passes door 1.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_STOCK; REALM=lab-two-doors
refresh
REF_URL=https://chatgpt.com/oauth/codex/client.json; ACC_URL=https://vscode.dev/oauth/client-metadata.json
sub RJ fetch_or_skip $REF_URL; sub AJ fetch_or_skip $ACC_URL
HOSTS=$(printf '%s\n%s\n' "$RJ" "$AJ" | uri_hosts)
realm_setup $REALM "$(json_array $HOSTS)"
DEF=$(kc "$KC/admin/realms/$REALM/components?type=$REG_POLICY" | jq -r '[.[]|select(.subType=="anonymous")|.providerId]|sort|join(",")')
[[ $DEF == *trusted-hosts* ]] || not_run "trusted-hosts is not among the default anonymous policies"
echo "default anonymous registration policies: $DEF"
auth $REALM $ACC_URL "$(jq -r '.redirect_uris[0]' <<<"$AJ")" $C_STOCK; expect positive-control accepted; HP=$H
auth $REALM $REF_URL "$(jq -r '.redirect_uris[0]' <<<"$RJ")" $C_STOCK; expect door1 parse; H1=$H; C1=$CAUSE
anon_register $REALM
case "$DS" in 4??) ;; 000) not_run "door 2: no response";; *) BAD+=("door 2: anonymous registration not refused (HTTP $DS)");; esac
echo "  door 1 (CIMD, refused document): HTTP $H1  $C1"
echo "  door 2 (anonymous DCR):          HTTP $DS  $DP"
record positive_control "$HP" door1_status "$H1" door1_cause "$C1" door2_status "$DS" door2_policy "$DP"
settle
echo "PASS: both doors closed in a default realm — CIMD refused at parse time, anonymous registration refused ($DP)."
