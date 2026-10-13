#!/usr/bin/env bash
# Reports the newest Keycloak 26.x release next to the versions pinned in versions.env.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/versions.env
latest=$(curl -s "https://quay.io/api/v1/repository/keycloak/keycloak/tag/?limit=100&onlyActiveTags=true" \
  | jq -r '.tags[].name' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
echo "measured (VERSIONS_DEFAULT): $VERSIONS_DEFAULT"
echo "pinned digests:              $(grep -oE 'KEYCLOAK_DIGEST_[0-9_]+' scripts/versions.env | sed 's/KEYCLOAK_DIGEST_//; s/_/./g' | paste -sd' ')"
echo "newest Keycloak on quay.io:  ${latest:-unknown}"
