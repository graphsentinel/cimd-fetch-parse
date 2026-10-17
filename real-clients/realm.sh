#!/usr/bin/env bash
# Realm for the real-agent trial: CIMD policy on, anonymous registration LOCKED (trusted hosts = []), one test user.
#   realm.sh <stock|ext>      (stock = 127.0.0.2:18100, ext = lenient-cimd on 127.0.0.2:18101)
# Allowlist = hosts of every *uri in the eight published documents + localhost + 127.0.0.1 + [::1]
# (the trial measures what the client itself does, so the [::1] step of check 09 is not repeated here).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1             # repository root
. scripts/common.sh
case "${1:?stock|ext}" in
  stock) KC=http://127.0.0.2:18100; EX=client-id-metadata-document;;
  ext)   KC=http://127.0.0.2:18101; EX=lenient-cimd;;
esac
REALM=agent-trial
refresh
fetch_vendor_docs
HOSTS="$(all_vendor_hosts) localhost [::1]"
realm_setup $REALM "$(json_array $HOSTS)" $EX
set_trusted_hosts $REALM '[]'
anon_register $REALM
[ "$DS" = 403 ] || not_run "anonymous registration not locked ($DS $DP)"
s=$(kc_status -X POST "$KC/admin/realms/$REALM/users" -H 'Content-Type: application/json' \
  -d '{"username":"alice","enabled":true,"email":"alice@lab.invalid","emailVerified":true,"firstName":"Alice","lastName":"Lab","credentials":[{"type":"password","value":"alice-lab-only","temporary":false}]}')
[ "$s" = 201 ] || not_run "user create answered $s"
s=$(kc "$KC/admin/realms/$REALM" | jq '.eventsEnabled=true | .eventsExpiration=86400 | .enabledEventTypes=["LOGIN","LOGIN_ERROR","CODE_TO_TOKEN","CODE_TO_TOKEN_ERROR","REFRESH_TOKEN","CLIENT_LOGIN"]' \
  | kc_status -X PUT "$KC/admin/realms/$REALM" -H 'Content-Type: application/json' -d @-)
[ "$s" = 204 ] || not_run "events answered $s"
echo "realm $REALM on $KC: executor $(loaded_executor $REALM), anonymous registration $DS ($DP), user alice"
# warm realm: same policy, used only to absorb Keycloak's first-fetch timeout before a client attempt
realm_setup agent-warm "$(json_array $HOSTS)" $EX
echo "realm agent-warm on $KC ready"
