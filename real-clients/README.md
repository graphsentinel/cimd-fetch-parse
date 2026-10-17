# Real clients against an MCP server behind Keycloak

The checks in `checks/` send each published CIMD document to Keycloak themselves and stop at the login page. This
directory runs the **real agent programs** instead: each client is pointed at a small OAuth-protected MCP server whose
authorization server is a lab Keycloak realm, and has to find its own way in.

The realm (`realm.sh`): Keycloak 26.8.0 from the lab, CIMD policy on, **anonymous dynamic registration locked**
(Trusted Hosts with no hosts: HTTP 403), one test user, events on. Two servers: stock (`127.0.0.2:18100`) and with this
repository's `lenient-cimd` executor (`127.0.0.2:18101`). Every attempt starts on a freshly created realm.

## What is recorded per attempt

Four records, so a result never rests on the client's own message:

| Record | Shows |
|---|---|
| Keycloak request record (the lab's recording proxy) | which `client_id` the client sent, and whether it tried dynamic registration |
| Keycloak events (`LOGIN`, `CODE_TO_TOKEN`) | whether Keycloak issued a token to that `client_id` |
| Keycloak server log | the server's reason for a refusal (`stock-refusal-causes.txt` pairs each refusal with its log line) |
| MCP server log (`mcp-server.py`) | whether the client then called the server with a token Keycloak accepts (`initialize`, `tools/list`, `tools/call`) |

Automated clients open their login URL in a stand-in browser (`fakebin/xdg-open` → `browser-driver.py`): it records what
the client put in the URL, logs in as the test user, accepts the consent screen and hands the code to the client's own
loopback callback. It never records codes or tokens.

## Results (Keycloak 26.8.0, 16–17 Oct 2026)

| Client (version) | How it registers | Stock Keycloak | With `lenient-cimd` |
|---|---|---|---|
| Copilot CLI 1.0.98 (person in the loop) | its CIMD URL | token, tools listed | token, tools listed |
| Hermes Agent 0.22.2 | its CIMD URL | token, tools listed | token, tools listed |
| Codex CLI 0.153.4 | its CIMD URL | refused at parse time | token, after its own fallback from Keycloak's full scope list (`invalid_scope`) to a narrower one; no MCP call measured |
| goose 1.55.0 | its CIMD URL | refused at parse time | token, tools listed, **tool called** |
| opencode 1.2.27 and 1.19.3 (latest release) | **dynamic registration**, not CIMD | 403 (registration locked) | 403 |
| VS Code 1.140 | — | not measured: the client never contacted the server | — |

Each automated client/server combination was run with and without a `scope` hint in the MCP server's 401 challenge (does the client follow the server's hint?), with the same outcome both times. Raw records,
the full table and the attempts that were not counted, with reasons: [evidence/real-clients/](../evidence/real-clients/).

Notes:
- As of 17 Oct 2026, opencode's CIMD support exists on its main branch, not in a released version (1.19.3 is the latest).
- Keycloak shows a consent screen to CIMD clients; the user approves it.
- Codex's `mcp login` ends after the token; whether Codex then uses it was not measured.

## Run it

Needs the lab on 26.8.0 (`VERSIONS=26.8.0 scripts/lab.sh build install`) and the clients under
`lab/.runtime/real-clients/clients/` (or `CLIENTS_DIR`): `codex` and `opencode` from `PATH`, goose 1.55.0
(`goose-dl/goose`), Hermes from source at tag v0.22.2 (`hermes-src/` + `hermes-venv/` with its `mcp` extra),
opencode 1.19.3 (`opencode-1.19.3/opencode`). Each client runs with its own temporary HOME; your own client settings are
not touched.

```bash
real-clients/realm.sh stock && real-clients/run.sh goose stock     # one attempt; prints its record directory
CLIENTS="codex goose hermes" real-clients/matrix.sh                 # each client x stock/ext x scope hint, fresh realm each
real-clients/manual.sh copilot stock                                # a person drives the client (Copilot CLI, VS Code)
real-clients/summarize.py                                          # the table, from the records
```

Records go to `lab/.runtime/real-clients/runs/` (not committed). The test user (`alice` / `alice-lab-only`) is lab-only.
