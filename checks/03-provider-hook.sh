#!/usr/bin/env bash
# 03 · Can a custom CIMD provider reach a document that fails to parse?
#
# Keycloak with this repository's logging-cimd provider (stock executor). The provider logs each entry into its two
# hooks with the client_id: determineFetchOperation (before the fetch) and createClientMetadata (the only provider
# method that receives the document). Two published documents: one accepted, one refused. Hook entries are counted
# in the server log window of that request, for that client_id only.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT; REALM=lab-provider-hook
refresh
grep -q 'cimd-provider-name=logging-cimd' <<<"$("$ENGINE" inspect --format '{{json .Config.Cmd}}' "$C_EXT" 2>/dev/null)" \
  || not_run "the logging-cimd provider is not selected on $C_EXT"
ACC_URL=https://vscode.dev/oauth/client-metadata.json; REF_URL=https://chatgpt.com/oauth/codex/client.json
sub AJ fetch_or_skip $ACC_URL; sub RJ fetch_or_skip $REF_URL
HOSTS=$(printf '%s\n%s\n' "$AJ" "$RJ" | uri_hosts)
realm_setup $REALM "$(json_array $HOSTS)"
hooks(){ grep -cF "ENTRY $1 clientId=$2" <<<"$WINDOW" || true; }
auth $REALM $ACC_URL "$(jq -r '.redirect_uris[0]' <<<"$AJ")" $C_EXT; expect accepted-document accepted
HA=$H; DA=$(hooks determineFetchOperation $ACC_URL); CA=$(hooks createClientMetadata $ACC_URL)
[ "$(outcome)" != accepted ] || { [ "$DA" -ge 1 ] && [ "$CA" -ge 1 ]; } || BAD+=("the accepted document did not pass through both hooks (d=$DA c=$CA)")
auth $REALM $REF_URL "$(jq -r '.redirect_uris[0]' <<<"$RJ")" $C_EXT; expect refused-document parse
HR=$H; XR=$CAUSE; DR=$(hooks determineFetchOperation $REF_URL); CR=$(hooks createClientMetadata $REF_URL)
printf '  accepted document (VS Code):     HTTP %s  determineFetchOperation=%s  createClientMetadata=%s\n' "$HA" "$DA" "$CA"
printf '  refused document (OpenAI Codex): HTTP %s  determineFetchOperation=%s  createClientMetadata=%s  %s\n' "$HR" "$DR" "$CR" "$XR"
record accepted_status "$HA" accepted_determine "$DA" accepted_create "$CA" refused_status "$HR" refused_determine "$DR" refused_create "$CR" refused_cause "$XR"
[ "$(outcome)" = network ] || { [ "$DR" -ge 1 ] && [ "$CR" -eq 0 ]; } || BAD+=("unexpected hook pattern on the refused document (d=$DR c=$CR)")
settle
echo "PASS: on a parse refusal determineFetchOperation ran ($DR), createClientMetadata never did."
