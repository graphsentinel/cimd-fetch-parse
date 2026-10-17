#!/usr/bin/env bash
# Act 4: a real agent program (goose 1.55.0) against an MCP server behind Keycloak, registration locked, through
# real-clients/ (fresh realm agent-trial each time). Every verdict line is read from that attempt's records (Keycloak
# events, Keycloak log, MCP server log), not from goose's own output.
# Needs goose (demo/install-goose.sh) and a model goose can use: by default Ollama at OLLAMA_HOST with GOOSE_MODEL
# (qwen3.6:35b); any goose provider works through GOOSE_PROVIDER/GOOSE_MODEL and that provider's own variables.
. "$(dirname "$0")/lib.sh"
RC=$ROOT/real-clients
export CLIENTS_DIR=${CLIENTS_DIR:-$RT/real-clients/clients} GOOSE_TIMEOUT=${GOOSE_TIMEOUT:-90}
export GOOSE_PROVIDER=${GOOSE_PROVIDER:-ollama} GOOSE_MODEL=${GOOSE_MODEL:-qwen3.6:35b} OLLAMA_HOST=${OLLAMA_HOST:-http://localhost:11434}
"$CLIENTS_DIR/goose-dl/goose" --version 2>/dev/null | grep -q '1\.55\.0' || { echo "NOT RUN: goose 1.55.0 not found: demo/install-goose.sh"; exit 77; }
if [ "$GOOSE_PROVIDER" = ollama ]; then
  curl -s --max-time 5 "$OLLAMA_HOST/api/tags" | jq -e --arg m "$GOOSE_MODEL" '[.models[]?.name]|index($m)' >/dev/null \
    || { echo "NOT RUN: Ollama at $OLLAMA_HOST has no model $GOOSE_MODEL (set GOOSE_MODEL, or GOOSE_PROVIDER)"; exit 77; }
fi
clean(){ sed -u -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s#/[^ ]*/runs/[^ ]*#<run dir>#g; s#(client_id=)[^ ]*#\1https://goose-docs.ai/oauth/client-metadata.json#; s/(user=alice)([A-Z])/\1\n\2/; s#(http://127\.0\.0\.2:1810[01]/realms/agent-trial/protocol/openid-connect/auth)\?.*#\1?…#' | grep --line-buffered -vE '^\s*$|^exit='; }
attempt(){ # attempt <stock|ext>
  "$RC/realm.sh" $1 > /dev/null 2>&1 || { echo "INVALID: realm setup failed (real-clients/realm.sh $1)"; return 1; }
  note "first, 2 warm-up requests for goose's URL go to a separate realm (agent-warm)"
  local log mark out pid f=""; log=$(mktemp); mark=$(mktemp)
  ( "$RC/run.sh" goose $1 > "$log" 2>&1 ) & pid=$!
  # only the record directory this attempt creates (newer than the marker), never an earlier one
  while kill -0 $pid 2>/dev/null; do f=$(find "$RT"/real-clients/runs -maxdepth 1 -name "*goose-$1" -newer "$mark" 2>/dev/null | head -1)
    [ -n "$f" ] && [ -f "$f/step-login.txt" ] && break; f=""; sleep 0.3; done
  rm -f "$mark"
  [ -n "$f" ] && tail -n +1 -f --pid=$pid "$f/step-login.txt" 2>/dev/null | clean | sed -u 's/^/  goose │ /'
  wait $pid; out=$(tail -1 "$log"); rm -f "$log"
  [ -d "$out" ] || { echo "INVALID: no record directory"; return 1; }
  python3 - "$out" <<'PY'
import json, os, re, sys
d = sys.argv[1]
def rows(f):
    p = os.path.join(d, f)
    return [json.loads(x) for x in open(p) if x.strip()] if os.path.exists(p) else []
ev = json.loads(open(os.path.join(d, "keycloak-state.txt")).readline())
tok = sum(e["n"] for e in ev if e["type"] == "CODE_TO_TOKEN")
br, mcp = rows("browser.jsonl"), rows("mcp-requests.jsonl")
calls = sorted({x["rpc"] for x in mcp if x.get("valid") and x.get("rpc") in ("tools/list", "tools/call")})
log = open(os.path.join(d, "keycloak-log.txt")).read() if os.path.exists(os.path.join(d, "keycloak-log.txt")) else ""
if re.search(r"SocketTimeout|ConnectException|UnknownHost", log): print("  INVALID: network timeout in the Keycloak log (not a result; run again)"); sys.exit(0)
first = br[0] if br else {}
st = (first.get("steps") or [{}])[0]
G, R, N, B = "\033[32m", "\033[31m", "\033[0m", "\033[1m"
print(f"  {B}record{N}  client_id   {first.get('client_id','-')}")
print(f"          Keycloak    HTTP {st.get('status','-')}  {st.get('message') or ('login page' if st.get('login_form') else '')}")
print(f"          token       {G+'issued (CODE_TO_TOKEN)'+N if tok else R+'none'+N}")
print(f"          MCP         {G+', '.join(calls)+' with a valid token'+N if calls else R+'no call with a token'+N}")
PY
}
title "Act 4 · a real agent, not the lab's requests: goose $("$CLIENTS_DIR/goose-dl/goose" --version | tr -d ' ')"
note "MCP server behind Keycloak $V · anonymous registration locked (403) · fresh realm each time"
note "goose uses its own CIMD URL; login by a scripted browser stand-in (alice / lab user) · model: $GOOSE_PROVIDER $GOOSE_MODEL"
step "Stock Keycloak"
attempt stock
step "Same agent, same MCP server: executor lenient-cimd"
attempt ext
step "Verdict lines above come from Keycloak's events and the MCP server's log, not from goose"
note "Records: $RT/real-clients/runs/"
wait_key
