#!/usr/bin/env bash
# manual.sh <vscode|copilot> <stock|ext>: a person drives a GUI / account-bound client; this records the same four
# sources as run.sh (Keycloak proxy, Keycloak events, MCP server log; the browser is the person's own).
#   1. ./manual.sh vscode stock          (fresh realm, MCP server on 127.0.0.1:19000 or :19001)
#   2. add the printed URL as an HTTP MCP server in the client, start it, log in as alice / alice-lab-only
#   3. press Enter here when the client shows the server's tools (or an error)
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$T/.." && pwd)
RUNS=${RUNS_DIR:-$ROOT/lab/.runtime/real-clients/runs}; CLIENTS=${CLIENTS_DIR:-$ROOT/lab/.runtime/real-clients/clients}
C=${1:?vscode|copilot}; S=${2:?stock|ext}
case $S in stock) KCP=18100; MP=19000;; ext) KCP=18101; MP=19001;; esac
"$T/realm.sh" $S > /dev/null || { echo "realm setup failed"; exit 1; }
export TRIAL_OUT=$RUNS/$(date -u +%Y%m%dT%H%M%SZ)-$C-$S; mkdir -p "$TRIAL_OUT"
echo "manual (person in the loop); CHALLENGE_SCOPE=" > "$TRIAL_OUT/config.txt"
P0=$(wc -l < "$ROOT/lab/.runtime/proxy/$KCP.jsonl" 2>/dev/null || echo 0)
python3 "$T/mcp-server.py" $MP "http://127.0.0.2:$KCP/realms/agent-trial" "$TRIAL_OUT/mcp-requests.jsonl" & MPID=$!
echo
echo "MCP server: http://127.0.0.1:$MP/mcp   (Keycloak: $S, realm agent-trial, anonymous registration locked)"
echo "Login: alice / alice-lab-only. Press Enter when the client shows the tools or an error."
read -r _
echo "what did the client show? (one line)"; read -r NOTE; echo "$NOTE" > "$TRIAL_OUT/person-note.txt"
kill $MPID 2>/dev/null
tail -n +$((P0+1)) "$ROOT/lab/.runtime/proxy/$KCP.jsonl" > "$TRIAL_OUT/keycloak-requests.jsonl"
( cd "$ROOT" && KC=http://127.0.0.2:$KCP bash -c '. scripts/common.sh; refresh
  kc "$KC/admin/realms/agent-trial/events?max=200" | jq -c "[.[] | {type, clientId, error}] | group_by(.type,.clientId,.error) | map({type:.[0].type, clientId:.[0].clientId, error:.[0].error, n:length})"' ) > "$TRIAL_OUT/keycloak-state.txt" 2>&1
python3 "$T/summarize.py" "$TRIAL_OUT"
