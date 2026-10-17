#!/usr/bin/env python3
"""For every attempt on stock Keycloak that was refused at the authorization endpoint, the server's own reason.
  refusal-causes.py <run dir>...      (reads `podman logs cimdlab-stock-26.8.0`)
Each LOGIN_ERROR event of realm agent-trial is paired with the executor line of the same thread just before it; the
event is then matched to the attempt whose authorization request (proxy record, or the browser record when the
client reached Keycloak on localhost without the proxy) happened within 3 s before it.
"""
import datetime, json, os, re, subprocess, sys

runs = [d for d in sys.argv[1:] if re.search(r"-stock(-scoped)?$", d)]
if not runs:
    sys.exit(0)

def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(datetime.timezone.utc)

attempts = []  # (time, run, client_id)
for d in runs:
    for x in (json.loads(l) for l in open(os.path.join(d, "keycloak-requests.jsonl")) if l.strip()) if os.path.exists(os.path.join(d, "keycloak-requests.jsonl")) else []:
        if x["method"] == "GET" and "/realms/agent-trial/protocol/openid-connect/auth" in x["path"]:
            m = re.search(r"client_id=([^&]+)", x["path"])
            attempts.append((ts(x["utc"]), os.path.basename(d), m.group(1) if m else "?"))
    if not any(a[1] == os.path.basename(d) for a in attempts) and os.path.exists(os.path.join(d, "browser.jsonl")):
        for b in (json.loads(l) for l in open(os.path.join(d, "browser.jsonl")) if l.strip()):
            if b.get("client_id"):
                attempts.append((ts(b["utc"]), os.path.basename(d), b["client_id"]))
start = min(a[0] for a in attempts) - datetime.timedelta(minutes=1) if attempts else None
if not start:
    sys.exit(0)
log = subprocess.run(["podman", "logs", "--since", start.strftime("%Y-%m-%dT%H:%M:%SZ"), "cimdlab-stock-26.8.0"],
                     capture_output=True, text=True).stdout + ""
prev = {}
print("# stock refusals in realm agent-trial: event time (UTC) | attempt | client_id the client sent | server's reason")
for line in log.splitlines():
    m = re.match(r"(\S+ \S+) +\w+ +\[[^\]]+\] \(([^)]+)\) (.*)", line)
    if not m:
        continue
    when, thread, msg = m.groups()
    if "ClientIdMetadataDocumentExecutor" in line:
        prev[thread] = msg
    if 'type="LOGIN_ERROR"' in line and 'realmName="agent-trial"' in line and thread in prev:
        t = datetime.datetime.strptime(when, "%Y-%m-%d %H:%M:%S,%f").replace(tzinfo=datetime.timezone.utc)
        near = [a for a in attempts if datetime.timedelta(0) <= t - a[0] <= datetime.timedelta(seconds=3)]
        cause = re.search(r'Unrecognized field "[a-z_]+"|SocketTimeoutException|not trusted domain[^,]*', prev[thread])
        a = near[-1] if near else (t, "-", "-")
        print(f"{t:%H:%M:%S} | {a[1]} | {a[2]} | {cause.group(0) if cause else prev[thread][:80]}")
