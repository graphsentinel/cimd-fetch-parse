#!/usr/bin/env bash
# 07 · What does the server advertise, and does a realm without a CIMD policy say it supports CIMD?
#
# M1  the discovery flag follows the server feature flag (two servers of the same version, with and without it)
# M2  a realm without a CIMD policy still advertises client_id_metadata_document_supported: true
# M3–M7  with anonymous DCR open, in a realm without and a realm with the CIMD policy: DCR works, the refused
#        document is refused by CIMD in both — for different reasons (unknown client vs fetch-and-parse), visible to
#        the caller as different messages in the same response.
# Not measured: whether a real client switches from DCR to CIMD because of the advertisement.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT
REF_URL=https://chatgpt.com/oauth/codex/client.json; ACC_URL=https://vscode.dev/oauth/client-metadata.json
VA=$(server_version "$KC_EXT"); VN=$(server_version "$KC_NOFLAG")
[ "$VA" != unknown ] && [ "$VA" = "$VN" ] || not_run "the two servers are not the same version ($VA / $VN)"
adv(){ local j; j=$(curl -s --max-time 10 "$1/realms/$2/.well-known/openid-configuration")
  [ "$(jq -r .issuer <<<"$j" 2>/dev/null)" != null ] && [ -n "$j" ] || not_run "no discovery document from $1 realm $2"
  jq -r 'if has("client_id_metadata_document_supported") then .client_id_metadata_document_supported|tostring else "absent" end' <<<"$j"; }
sub M1A adv "$KC_EXT" master; sub M1N adv "$KC_NOFLAG" master
echo "M1 master realm: feature on=$M1A  feature off=$M1N"
refresh
sub RJ fetch_or_skip $REF_URL; sub AJ fetch_or_skip $ACC_URL
RRU=$(jq -r '.redirect_uris[0]' <<<"$RJ"); ARU=$(jq -r '.redirect_uris[0]' <<<"$AJ")
HOSTS=$(printf '%s\n%s\n' "$RJ" "$AJ" | uri_hosts)

RA=lab-adv-nopolicy; realm_fresh $RA
[ "$(kc "$KC/admin/realms/$RA/client-policies/profiles" | jq "[.profiles[]?|select(.name==\"$PROFILE\")]|length")" = 0 ] || not_run "realm A has a CIMD profile"
sub M2 adv "$KC" $RA; echo "M2 realm without a CIMD policy advertises: $M2"
set_trusted_hosts $RA '["localhost","127.0.0.1"]'
anon_register $RA; DA=$DS
case "$DA" in 2??) ;; *) not_run "realm A: anonymous DCR could not be opened ($DA)";; esac
auth $RA $REF_URL "$RRU" $C_EXT; expect realmA-cimd refused; CA=$H; MA=$MSG

RB=lab-adv-policy; realm_setup $RB "$(json_array $HOSTS)"
set_trusted_hosts $RB '["localhost","127.0.0.1"]'
anon_register $RB; DB=$DS
case "$DB" in 2??) ;; *) not_run "realm B: anonymous DCR could not be opened ($DB)";; esac
auth $RB $ACC_URL "$ARU" $C_EXT; expect positive-control accepted; PK=$H
auth $RB $REF_URL "$RRU" $C_EXT; expect realmB-cimd parse; CB=$H; XB=$CAUSE; MB=$MSG
echo "  realm A (no CIMD policy): DCR=$DA  CIMD=$CA  caller: '${MA:-?}'"
echo "  realm B (CIMD policy):    DCR=$DB  CIMD=$CB  caller: '${MB:-?}'  server: $XB   (positive control $PK)"
record m1_feature_on "$M1A" m1_feature_off "$M1N" m2_no_policy_realm "$M2" realmA_dcr "$DA" realmA_cimd "$CA" realmA_message "${MA:--}" \
       realmB_dcr "$DB" realmB_cimd "$CB" realmB_message "${MB:--}" realmB_cause "$XB" positive_control "$PK"
{ [ "$M1A" = true ] && [ "$M1N" = absent ]; } || BAD+=("advertisement does not follow the feature flag (on=$M1A off=$M1N)")
[ "$M2" = true ] || BAD+=("realm without a CIMD policy does not advertise ($M2)")
{ [ -n "$MA" ] && [ -n "$MB" ] && [ "$MA" != "$MB" ]; } || BAD+=("the two refusals do not differ in the caller message ('$MA' / '$MB')")
settle
echo "PASS: every realm advertises CIMD; with DCR open, both realms refuse the document — '$MA' vs '$MB'."
