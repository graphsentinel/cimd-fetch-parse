#!/usr/bin/env python3
"""Tabulates the real-agent trial: one row per attempt directory under $RUNS_DIR (default lab/.runtime/real-clients/runs) or the ones given.
Columns come from four independent records, never from the client's own claim alone:
  client_id / DCR     - Keycloak's recording proxy (authorization requests, registration POSTs)
  authorize outcome   - the browser driver (what Keycloak answered the URL the client opened)
  token issued        - Keycloak's own events (CODE_TO_TOKEN for that client_id)
  MCP call with token - the MCP server's log (a request whose bearer Keycloak's userinfo accepted)
"""
import glob, json, os, re, sys, urllib.parse

T = os.path.dirname(os.path.abspath(__file__))


def jl(p):
    try:
        return [json.loads(x) for x in open(p) if x.strip()]
    except OSError:
        return []


rows = []
RUNS = os.environ.get("RUNS_DIR") or os.path.join(os.path.dirname(T), "lab", ".runtime", "real-clients", "runs")
for d in sys.argv[1:] or sorted(glob.glob(os.path.join(RUNS, "2026*"))):
    name = os.path.basename(d)
    m = re.match(r"\d{8}T\d{6}Z-(\w+?)-(stock|ext)(-scoped)?$", name)
    if not m:
        continue
    client, server, scoped = m.group(1), m.group(2), bool(m.group(3))
    kq = jl(os.path.join(d, "keycloak-requests.jsonl"))
    auth = [urllib.parse.parse_qs(urllib.parse.urlparse(x["path"]).query) for x in kq
            if x["method"] == "GET" and "/realms/agent-trial/protocol/openid-connect/auth" in x["path"]]
    cids = sorted({a.get("client_id", ["?"])[0] for a in auth})
    dcr = [x["status"] for x in kq if x["method"] == "POST" and "clients-registrations" in x["path"]]
    br = jl(os.path.join(d, "browser.jsonl"))
    outcomes = [b["result"] + (f"({b.get('callback_error_description') or b['steps'][0].get('message') or ''})"[:70]
                               if b["result"] != "code_delivered_to_client" else "") for b in br]
    ev = []
    try:
        ev = json.loads(open(os.path.join(d, "keycloak-state.txt")).readline())
    except (OSError, ValueError):
        pass
    tok = sum(e["n"] for e in ev if e["type"] == "CODE_TO_TOKEN")
    tok_err = [f"{e['type']}:{e.get('error')}" for e in ev if e["type"].endswith("_ERROR")]
    mcp = jl(os.path.join(d, "mcp-requests.jsonl"))
    used = sorted({x["rpc"] for x in mcp if x.get("valid")})
    log = (open(os.path.join(d, "keycloak-log.txt")).read() if os.path.exists(os.path.join(d, "keycloak-log.txt")) else "")
    net = len(re.findall(r"SocketTimeout|ConnectException|UnknownHost", log))
    rows.append((client, server, "scope hint" if scoped else "-", ",".join(cids) or "-", ",".join(map(str, dcr)) or "-",
                 "; ".join(outcomes) or (("person: " + open(os.path.join(d, "person-note.txt")).read().strip()[:80])
                                         if os.path.exists(os.path.join(d, "person-note.txt")) else "no browser opened"), tok, ",".join(sorted(set(tok_err))) or "-",
                 ",".join(used) or "-", net, name))

hdr = ("client", "Keycloak", "challenge", "client_id used", "DCR POST", "authorize outcome(s)", "tokens issued",
       "Keycloak errors", "MCP calls with valid token", "net timeouts in log", "run")
print("| " + " | ".join(hdr) + " |\n|" + "---|" * len(hdr))
for r in rows:
    print("| " + " | ".join(str(c).replace("|", "/") for c in r) + " |")
