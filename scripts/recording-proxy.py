#!/usr/bin/env python3
"""Recording reverse proxy in front of one Keycloak: every request and its raw response, as JSONL.

The checks talk to 127.0.0.2:<port>; this proxy forwards to Keycloak on 127.0.0.1:<port> (same port, so nothing in
the checks changes). Each line: utc, run, port, method, path (with query), status, Location, response body.

Never written: request headers (the admin bearer token), request bodies (the admin password), token responses.
Secret-looking fields in response bodies are replaced by "<redacted>".
The run label is read per request from the file named by RUN_LABEL_FILE (scripts/lab.sh writes it).

  recording-proxy.py <listen-ip> <port> <target-ip> <jsonl>
"""
import datetime
import http.client
import http.server
import json
import os
import re
import sys
import threading

LISTEN, PORT, TARGET, OUT = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
LABEL_FILE = os.environ.get("RUN_LABEL_FILE", "")
LOCK = threading.Lock()
SECRET = re.compile(r'"(access_token|refresh_token|id_token|registration_access_token|client_secret|secret|value|'
                    r'password|hashedSaltedValue|salt|privateKey|certificate)"\s*:\s*"[^"]*"')
MAX_BODY = 64 * 1024


def label():
    try:
        with open(LABEL_FILE) as f:
            return f.read().strip() or None
    except OSError:
        return None


def redact(body: bytes) -> str:
    return SECRET.sub(lambda m: f'"{m.group(1)}":"<redacted>"', body[:MAX_BODY].decode("utf-8", "replace"))


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def forward(self):
        n = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(n) if n else None
        headers = {k: v for k, v in self.headers.items() if k.lower() not in ("connection", "keep-alive", "proxy-connection")}
        start = datetime.datetime.now(datetime.timezone.utc)
        conn = http.client.HTTPConnection(TARGET, PORT, timeout=120)
        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            r = conn.getresponse()
            data, status, rh = r.read(), r.status, r.getheaders()
        except Exception as e:  # no upstream: 502, recorded as such
            data, status, rh = json.dumps({"proxy_error": type(e).__name__}).encode(), 502, []
        finally:
            conn.close()
        self.send_response(status)
        for k, v in rh:
            if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(k, v)
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        path = self.path.split("?")[0]
        token_call = path.endswith("/protocol/openid-connect/token")
        row = {"utc": start.isoformat(), "run": label(), "port": PORT, "method": self.command,
               "path": path if token_call else self.path, "status": status,
               "location": dict((k.lower(), v) for k, v in rh).get("location"),
               "body": "<token response, not recorded>" if token_call else redact(data)}
        with LOCK, open(OUT, "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_PATCH = forward


if __name__ == "__main__":
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    server = http.server.ThreadingHTTPServer((LISTEN, PORT), Proxy)
    sys.stderr.write(f"recording-proxy {LISTEN}:{PORT} -> {TARGET}:{PORT} ({OUT})\n")
    server.serve_forever()
