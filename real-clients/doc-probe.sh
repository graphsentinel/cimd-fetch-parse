#!/usr/bin/env bash
# doc-probe.sh: published CIMD documents that are not in the ten checks, sent to Keycloak by the lab itself (like
# checks 01/05): stock and lenient-cimd, reason from the server log of that request. Zed's real redirect has a port.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
for S in stock ext; do
  KCB=$([ $S = stock ] && echo http://127.0.0.2:18100 || echo http://127.0.0.2:18101); C=cimdlab-$S-26.8.0
  EX=$([ $S = stock ] && echo client-id-metadata-document || echo lenient-cimd)
  KC=$KCB OBS_FILE=/dev/null S=$S C=$C EX=$EX bash -c '. scripts/common.sh; refresh
    realm_setup doc-probe "[\"127.0.0.1\",\"zed.dev\",\"cdn.zed.dev\",\"ampcode.com\"]" $EX
    for e in "zed|https://zed.dev/oauth/client-metadata.json|http://127.0.0.1/callback" "zed (port)|https://zed.dev/oauth/client-metadata.json|http://127.0.0.1:45678/callback" "amp|https://ampcode.com/oauth/client-metadata.json|https://ampcode.com/auth/mcp/callback"; do
      IFS="|" read -r n cid ru <<<"$e"; auth doc-probe "$cid" "$ru" $C
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$(utc)" "$S" "$n" "$cid" "$H" "$(outcome) ${CAUSE}"
    done'
done
