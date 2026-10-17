#!/usr/bin/env python3
"""Minimal MCP server (streamable HTTP, JSON responses) protected by Keycloak, per the MCP authorization spec:
no/invalid bearer -> 401 + WWW-Authenticate resource_metadata -> RFC 9728 metadata naming the Keycloak realm.
A bearer is valid when Keycloak's userinfo endpoint accepts it. One tool: `whoami`.

  mcp-server.py <port> <issuer> <log.jsonl>
Every request is logged (method, path, bearer present/valid, JSON-RPC method, status); token values never are.
"""
import datetime, http.server, json, os, sys, threading, urllib.request

PORT, ISSUER, LOG = int(sys.argv[1]), sys.argv[2].rstrip("/"), sys.argv[3]
BASE = f"http://127.0.0.1:{PORT}"
PRM = {"resource": f"{BASE}/mcp", "authorization_servers": [ISSUER], "scopes_supported": ["openid"],
       "bearer_methods_supported": ["header"]}
LOCK = threading.Lock()


def userinfo(token):
    req = urllib.request.Request(f"{ISSUER}/protocol/openid-connect/userinfo", headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r)
    except Exception:
        return None


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def out(self, status, body=None, headers=(), rec=None):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        if body is not None:
            self.send_header("Content-Type", "application/json")
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        row = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "method": self.command,
               "path": self.path, "status": status, "ua": self.headers.get("User-Agent", "")}
        row.update(rec or {})
        with LOCK, open(LOG, "a") as f:
            f.write(json.dumps(row) + "\n")

    def do_GET(self):
        if self.path.startswith("/.well-known/oauth-protected-resource"):
            return self.out(200, PRM)
        if self.path.startswith("/mcp"):
            return self.out(405, {"error": "SSE stream not offered"}, [("Allow", "POST")])
        self.out(404, {"error": "not found"})

    def do_DELETE(self):
        self.out(405, {"error": "no sessions"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            msg = json.loads(raw or b"{}")
        except ValueError:
            msg = {}
        rpc = msg.get("method") if isinstance(msg, dict) else "batch"
        auth = self.headers.get("Authorization", "")
        sc = os.environ.get("CHALLENGE_SCOPE")  # optional scope hint in the 401 challenge (MCP spec: clients use it first)
        challenge = [("WWW-Authenticate", f'Bearer resource_metadata="{BASE}/.well-known/oauth-protected-resource/mcp"'
                      + (f', scope="{sc}"' if sc else ""))]
        if not auth.lower().startswith("bearer "):
            return self.out(401, {"error": "unauthorized"}, challenge, {"bearer": False, "rpc": rpc})
        who = userinfo(auth[7:])
        if who is None:
            return self.out(401, {"error": "invalid_token"}, challenge, {"bearer": True, "valid": False, "rpc": rpc})
        rec = {"bearer": True, "valid": True, "rpc": rpc, "user": who.get("preferred_username")}
        mid = msg.get("id")
        if rpc == "initialize":
            pv = (msg.get("params") or {}).get("protocolVersion", "2025-06-18")
            return self.out(200, {"jsonrpc": "2.0", "id": mid, "result": {
                "protocolVersion": pv, "capabilities": {"tools": {}},
                "serverInfo": {"name": "cimd-agent-trial", "version": "1"}}}, rec=rec)
        if rpc and rpc.startswith("notifications/"):
            return self.out(202, None, rec=rec)
        if rpc == "tools/list":
            return self.out(200, {"jsonrpc": "2.0", "id": mid, "result": {"tools": [{
                "name": "whoami", "description": "Returns the authenticated user",
                "inputSchema": {"type": "object", "properties": {}}}]}}, rec=rec)
        if rpc == "tools/call":
            return self.out(200, {"jsonrpc": "2.0", "id": mid, "result": {"content": [
                {"type": "text", "text": f"user={who.get('preferred_username')}"}]}}, rec=rec)
        if rpc == "ping":
            return self.out(200, {"jsonrpc": "2.0", "id": mid, "result": {}}, rec=rec)
        self.out(200, {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found"}}, rec=rec)


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
