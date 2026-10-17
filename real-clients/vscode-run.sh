#!/usr/bin/env bash
# vscode-run.sh <stock|ext>: VS Code, driven by Playwright (Electron) on a virtual display, against the MCP server behind
# Keycloak. Own realm (vscode-trial) and MCP port (19010/19011), so it can run next to matrix.sh. Isolated VS Code profile
# (--user-data-dir, --extensions-dir): your own VS Code settings and extensions are not used or touched.
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$T/.." && pwd); S=${1:?stock|ext}
RUNS=${RUNS_DIR:-$ROOT/lab/.runtime/real-clients/runs}; CLIENTS=${CLIENTS_DIR:-$ROOT/lab/.runtime/real-clients/clients}
case $S in stock) KCP=18100; MP=19010; EX=client-id-metadata-document;; ext) KCP=18101; MP=19011; EX=lenient-cimd;; esac
REALM=vscode-trial; KCB=http://127.0.0.2:$KCP; AS_HOST=${AS_HOST:-localhost}; ISSUER=http://$AS_HOST:$KCP/realms/$REALM; export AS_HOSTPORT=$AS_HOST:$KCP
export TRIAL_OUT=$RUNS/$(date -u +%Y%m%dT%H%M%SZ)-vscode-$S; mkdir -p "$TRIAL_OUT/profile" "$TRIAL_OUT/extensions" "$TRIAL_OUT/workspace/.vscode" "$TRIAL_OUT/home"
echo "BROWSER_DRIVER=${BROWSER_DRIVER:-stand-in}; realm=$REALM; issuer=$ISSUER; VS Code $(/usr/share/code/bin/code --version | head -1)" > "$TRIAL_OUT/config.txt"
# realm: same policy as realm.sh (CIMD policy, anonymous registration locked, user alice, events on)
( cd "$ROOT" && KC=$KCB bash -c '. scripts/common.sh; refresh; fetch_vendor_docs; HOSTS="$(all_vendor_hosts) localhost [::1] vscode.dev"
  realm_setup '$REALM' "$(json_array $HOSTS)" '$EX'; set_trusted_hosts '$REALM' "[]"; anon_register '$REALM'; [ "$DS" = 403 ] || not_run "registration not locked"
  s=$(kc_status -X POST "$KC/admin/realms/'$REALM'/users" -H "Content-Type: application/json" -d "{\"username\":\"alice\",\"enabled\":true,\"email\":\"alice@lab.invalid\",\"emailVerified\":true,\"firstName\":\"Alice\",\"lastName\":\"Lab\",\"credentials\":[{\"type\":\"password\",\"value\":\"alice-lab-only\",\"temporary\":false}]}"); [ "$s" = 201 ] || not_run "user $s"
  kc "$KC/admin/realms/'$REALM'" | jq ".eventsEnabled=true|.eventsExpiration=86400|.enabledEventTypes=[\"LOGIN\",\"LOGIN_ERROR\",\"CODE_TO_TOKEN\",\"CODE_TO_TOKEN_ERROR\"]" | kc_status -X PUT "$KC/admin/realms/'$REALM'" -H "Content-Type: application/json" -d @- >/dev/null' ) > "$TRIAL_OUT/realm.txt" 2>&1 || { echo "realm setup failed"; cat "$TRIAL_OUT/realm.txt"; exit 1; }
for i in 1 2; do curl -s -o /dev/null --max-time 30 "$KCB/realms/agent-warm/protocol/openid-connect/auth?client_id=https%3A%2F%2Fvscode.dev%2Foauth%2Fclient-metadata.json&redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2F&response_type=code&scope=openid&state=warm"; done
printf '{"servers":{"cimd-%s":{"type":"http","url":"http://127.0.0.1:%s/mcp"}}}\n' $S $MP > "$TRIAL_OUT/workspace/.vscode/mcp.json"
P0=$(wc -l < "$ROOT/lab/.runtime/proxy/$KCP.jsonl" 2>/dev/null || echo 0)
python3 "$T/mcp-server.py" $MP "$ISSUER" "$TRIAL_OUT/mcp-requests.jsonl" & MPID=$!; sleep 1
( export PATH=$T/fakebin:$PATH BROWSER=$T/fakebin/xdg-open CLIENTS_DIR=$CLIENTS
  unset WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
  NODE_PATH=$CLIENTS/pw/node_modules PLAYWRIGHT_BROWSERS_PATH=$CLIENTS/pw/browsers PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64 \
  timeout ${VSCODE_TIMEOUT:-240} xvfb-run -a -s "-screen 0 1600x1000x24" node "$T/vscode-playwright.js" "cimd-$S" ) > "$TRIAL_OUT/step-login.txt" 2>&1
echo "exit=$?" >> "$TRIAL_OUT/step-login.txt"
sleep 2; kill $MPID 2>/dev/null
tail -n +$((P0+1)) "$ROOT/lab/.runtime/proxy/$KCP.jsonl" | jq -c "select(.path|test(\"/realms/$REALM/\"))" > "$TRIAL_OUT/keycloak-requests.jsonl" 2>/dev/null
mkdir -p "$TRIAL_OUT/vscode-logs"; find "$TRIAL_OUT/profile/logs" -type f \( -iname '*mcp*' -o -iname 'renderer.log' -o -iname 'exthost.log' \) -exec cp {} "$TRIAL_OUT/vscode-logs/" \; 2>/dev/null
( cd "$ROOT" && KC=$KCB bash -c '. scripts/common.sh; refresh
  kc "$KC/admin/realms/'$REALM'/events?max=200" | jq -c "[.[] | {type, clientId, error}] | group_by(.type,.clientId,.error) | map({type:.[0].type, clientId:.[0].clientId, error:.[0].error, n:length})"' ) > "$TRIAL_OUT/keycloak-state.txt" 2>&1
podman logs --since "$(date -u -d '-6 min' +%FT%TZ)" cimdlab-$S-26.8.0 2>&1 | grep -iE 'cimd|client.?metadata|Unrecognized|not trusted|realmName="'$REALM'"' > "$TRIAL_OUT/keycloak-log.txt"
rm -rf "$TRIAL_OUT/profile" "$TRIAL_OUT/extensions" "$TRIAL_OUT/home"   # VS Code's own profile: may hold the token; never kept
echo "$TRIAL_OUT"
