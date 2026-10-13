#!/usr/bin/env python3
"""Local HTTPS metadata server for the lab: serves the scenario documents the checks write.

  GET /c/<name>.json   the document <SCENARIOS>/<name>.json (404 if missing)
  GET /p/<anything>    a probe target (redirect URIs point here); answers {}
  GET /_requests       every request seen so far (this endpoint itself is not recorded)

Every request is appended to REQUEST_LOG as JSON (path, kind, user agent, time, source address).
Environment: MD_PORT (8443), MD_CERT, MD_KEY, SCENARIOS, REQUEST_LOG.
"""
import datetime
import http.server
import json
import os
import ssl
import sys
import threading
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = os.environ.get("SCENARIOS", os.path.join(HERE, "..", "lab", ".runtime", "scenarios"))
LOG = os.environ.get("REQUEST_LOG", os.path.join(HERE, "..", "lab", ".runtime", "metadata-requests.jsonl"))
LOCK = threading.Lock()


def record(handler, kind):
    row = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "path": handler.path, "kind": kind,
           "user_agent": handler.headers.get("user-agent"), "source": handler.client_address[0]}
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with LOCK, open(LOG, "a") as f:
        f.write(json.dumps(row) + "\n")


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/_requests":
            try:
                with open(LOG) as f:
                    rows = [json.loads(x) for x in f if x.strip()]
            except FileNotFoundError:
                rows = []
            self.send(200, json.dumps(rows).encode())
            return
        if path.startswith("/c/") and path.endswith(".json"):
            record(self, "document")
            p = os.path.join(SCENARIOS, os.path.basename(path[3:]))
            if not os.path.exists(p):
                self.send(404, b'{"error":"no such scenario"}')
                return
            with open(p, "rb") as f:
                self.send(200, f.read())
            return
        if path.startswith("/p/"):
            record(self, "probe")
            self.send(200, b"{}")
            return
        record(self, "unknown")
        self.send(404, b'{"error":"no such path"}')


def main():
    port = int(os.environ.get("MD_PORT", "8443"))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.environ["MD_CERT"], os.environ["MD_KEY"])
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write(f"metadata server on https://0.0.0.0:{port}, scenarios in {SCENARIOS}\n")
    srv.serve_forever()


if __name__ == "__main__":
    main()
