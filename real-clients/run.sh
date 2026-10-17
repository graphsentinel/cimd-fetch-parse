#!/usr/bin/env bash
# run.sh <codex|opencode> <stock|ext>: one real-client OAuth attempt against the MCP server behind Keycloak.
# Isolated HOME per attempt; output in runs/<utc>-<client>-<server>/.
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$T/.." && pwd)
RUNS=${RUNS_DIR:-$ROOT/lab/.runtime/real-clients/runs}; CLIENTS=${CLIENTS_DIR:-$ROOT/lab/.runtime/real-clients/clients}
C=$1; S=$2
case $S in stock) KCP=18100; MP=19000;; ext) KCP=18101; MP=19001;; esac
ISSUER=http://127.0.0.2:$KCP/realms/agent-trial
export TRIAL_OUT=$RUNS/$(date -u +%Y%m%dT%H%M%SZ)-$C-$S${CHALLENGE_SCOPE:+-scoped}; mkdir -p "$TRIAL_OUT/home"
echo "CHALLENGE_SCOPE=${CHALLENGE_SCOPE:-}" > "$TRIAL_OUT/config.txt"
python3 "$T/mcp-server.py" $MP "$ISSUER" "$TRIAL_OUT/mcp-requests.jsonl" & MPID=$!; sleep 1
case $C in codex) CID=https://chatgpt.com/oauth/codex/client.json;; opencode|opencode19) CID=https://opencode.ai/oauth/opencode/client.json;; goose) CID=https://goose-docs.ai/oauth/client-metadata.json;; hermes) CID=https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json;; esac
for i in 1 2; do curl -s -o /dev/null -w "warm %{http_code}\n" --max-time 30 "http://127.0.0.2:$KCP/realms/agent-warm/protocol/openid-connect/auth?client_id=$(jq -rn --arg v "$CID" '$v|@uri')&redirect_uri=$(jq -rn --arg v "http://127.0.0.1:1/callback" '$v|@uri')&response_type=code&scope=openid" >> "$TRIAL_OUT/config.txt"; done
P0=$(wc -l < "$ROOT/lab/.runtime/proxy/$KCP.jsonl" 2>/dev/null || echo 0)
export HOME=$TRIAL_OUT/home XDG_CONFIG_HOME=$TRIAL_OUT/home/.config XDG_DATA_HOME=$TRIAL_OUT/home/.local/share \
       XDG_STATE_HOME=$TRIAL_OUT/home/.local/state CODEX_HOME=$TRIAL_OUT/home/.codex \
       PATH=$T/fakebin:$PATH BROWSER=$T/fakebin/xdg-open DISPLAY=:fake
mkdir -p "$CODEX_HOME" "$XDG_CONFIG_HOME"
cd "$TRIAL_OUT"
case $C in
  codex)
    timeout 150 codex mcp add trial --url http://127.0.0.1:$MP/mcp > step-add.txt 2>&1
    grep -q 'Successfully logged in' step-add.txt || { timeout 120 codex mcp login trial > step-login.txt 2>&1; echo "exit=$?" >> step-login.txt; }
    timeout 60 codex mcp list > step-list.txt 2>&1;;
  opencode19)
    printf '{"$schema":"https://opencode.ai/config.json","mcp":{"trial":{"type":"remote","url":"http://127.0.0.1:%s/mcp"}}}\n' $MP > opencode.json
    timeout 120 $CLIENTS/opencode-1.19.3/opencode mcp auth trial > step-login.txt 2>&1 < /dev/null; echo "exit=$?" >> step-login.txt
    timeout 90 $CLIENTS/opencode-1.19.3/opencode mcp list > step-list.txt 2>&1 < /dev/null;;
  opencode)
    printf '{"$schema":"https://opencode.ai/config.json","mcp":{"trial":{"type":"remote","url":"http://127.0.0.1:%s/mcp"}}}\n' $MP > opencode.json
    timeout 120 opencode mcp auth trial > step-login.txt 2>&1 < /dev/null; echo "exit=$?" >> step-login.txt
    timeout 90 opencode mcp list > step-list.txt 2>&1 < /dev/null;;
  hermes)
    export HERMES_HOME=$HOME/.hermes; mkdir -p $HERMES_HOME
    printf 'mcp_servers:\n  trial:\n    url: "http://127.0.0.1:%s/mcp"\n    auth: oauth\n    oauth:\n      timeout: 90\n' $MP > $HERMES_HOME/config.yaml
    HP="$CLIENTS/hermes-venv/bin/python -m hermes_cli.main"
    ( cd $CLIENTS/hermes-src && timeout 150 $HP mcp login trial ) > step-login.txt 2>&1 < /dev/null; echo "exit=$?" >> step-login.txt
    ( cd $CLIENTS/hermes-src && timeout 90 $HP mcp test trial ) > step-list.txt 2>&1 < /dev/null;;
  goose)
    export GOOSE_PROVIDER=ollama GOOSE_MODEL=qwen3.6:35b OLLAMA_HOST=http://localhost:11434 GOOSE_DISABLE_KEYRING=1
    timeout ${GOOSE_TIMEOUT:-300} $CLIENTS/goose-dl/goose run --no-session -t "Call the whoami tool once and print exactly what it returns." \
      --with-streamable-http-extension http://127.0.0.1:$MP/mcp > step-login.txt 2>&1 < /dev/null; echo "exit=$?" >> step-login.txt;;
esac
sleep 2; kill $MPID 2>/dev/null
tail -n +$((P0+1)) "$ROOT/lab/.runtime/proxy/$KCP.jsonl" > keycloak-requests.jsonl 2>/dev/null
podman logs --since "$(date -u -d '-4 min' +%FT%TZ)" cimdlab-$([ $S = stock ] && echo stock || echo ext)-26.8.0 2>&1 | grep -iE 'cimd|client.?metadata|Unrecognized|not trusted|LOGIN|CODE_TO_TOKEN|invalid' > keycloak-log.txt
# Keycloak's own record of what happened (events: LOGIN, CODE_TO_TOKEN = a token was issued to that client_id)
( cd "$ROOT" && KC=http://127.0.0.2:$KCP bash -c '. scripts/common.sh; refresh
  kc "$KC/admin/realms/agent-trial/events?max=200" | jq -c "[.[] | {type, clientId, error}] | group_by(.type,.clientId,.error) | map({type:.[0].type, clientId:.[0].clientId, error:.[0].error, n:length})"
  kc "$KC/admin/realms/agent-trial/clients?max=500" | jq -c "[.[]|.clientId|select(test(\"^https?://\"))]"' ) > keycloak-state.txt 2>&1
echo "$TRIAL_OUT"
