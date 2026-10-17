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

The login itself is done by a **real headless Chromium driven by Playwright** (`browser-playwright.js`, with a
screenshot of every step): it opens the URL the client opened (the client's opener is redirected to it through
`fakebin/xdg-open`; a client that only prints the URL has it picked up from its output), logs in as the test user,
accepts the consent screen and lands on the client's own loopback callback. The first runs used a scripted stand-in
(`browser-driver.py`, `BROWSER_DRIVER` unset) with the same results. Copilot CLI was driven by a person. Codes and tokens
are never recorded.

## Results (Keycloak 26.8.0, 17 Oct 2026, Playwright)

| Client program | How it registers | Stock Keycloak | With `lenient-cimd` |
|---|---|---|---|
| Copilot CLI 1.0.98 (person in the loop) | its CIMD URL | token, tools listed | token, tools listed |
| Hermes Agent 0.22.2 | its CIMD URL | token, tools listed | token, tools listed |
| goose 1.55.0 | its CIMD URL | refused at parse time | token, tools listed, **tool called** |
| Codex CLI 0.153.4 | its CIMD URL | refused at parse time | token, after its own fallback from Keycloak's full scope list (`invalid_scope`) to fewer scopes; no MCP call measured |
| opencode development build, default branch `dev` a49f179 (unreleased) | its CIMD URL | refused at parse time | token, tools listed |
| opencode 1.2.27 and 1.19.3 (released) | **dynamic registration**, not CIMD | 403 (registration locked) | 403 |
| mcp-remote 0.15.1 (defaults, no `--client-metadata-url`) | **dynamic registration** | 403 (registration locked) | 403 |
| VS Code 1.140 (`vscode-run.sh`) | — | reached the MCP server and Keycloak's metadata; its sign-in did not start under automation: not measured | — |

Each automated combination in this table (not VS Code) was run with and without a `scope` hint in the MCP server's 401
challenge, with the same outcome both times; that alone does not show whether a client follows the hint. Every stock refusal above is paired with
its own server-log line (`refusal-causes.py`). Raw records, screenshots, the full tables and the attempts that were not
counted: [evidence/real-clients/](../evidence/real-clients/).

Notes:
- opencode `dev` refuses to send its token request to a plain-http authorization server unless it is `localhost`; for
  it (and for the VS Code runs) the MCP server names Keycloak on `localhost` (`AS_HOST`), without the recording proxy.
  In a real deployment Keycloak is on https; this is a lab constraint, not a finding.
- As of 17 Oct 2026, opencode's CIMD support exists on its default branch, not in a released version (1.19.3 is the
  latest).
- Keycloak shows a consent screen to CIMD clients; the user approves it.
- Codex's `mcp login` ends after the token; whether Codex then uses it was not measured.
- `doc-probe.sh`: two more published documents (Zed, Amp), sent by the lab itself like checks 01/05: accepted on stock.

## Run it

Needs the lab on 26.8.0 (`VERSIONS=26.8.0 scripts/lab.sh build install`) and the clients under
`lab/.runtime/real-clients/clients/` (or `CLIENTS_DIR`): `codex` and `opencode` from `PATH`, goose 1.55.0
(`goose-dl/goose`), Hermes from source at tag v0.22.2 (`hermes-src/` + `hermes-venv/` with its `mcp` extra), opencode
1.19.3 (`opencode-1.19.3/opencode`), opencode `dev` from source (`opencode-dev/` + bun 1.4.2 in `bun/`), mcp-remote via
`npx`, Playwright 1.56.1 with its headless Chromium in `pw/` (on Ubuntu 26.04: `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=
ubuntu24.04-x64`). Each client runs with its own temporary HOME and no desktop session; your own client settings,
accounts and browser are not used.

```bash
export BROWSER_DRIVER=playwright
real-clients/realm.sh stock && real-clients/run.sh goose stock    # one attempt; prints its record directory
real-clients/matrix.sh                                           # every client x stock/ext x scope hint, fresh realm each
real-clients/manual.sh copilot stock                             # a person drives the client (Copilot CLI)
real-clients/vscode-run.sh stock                                 # VS Code on a virtual display (Xvfb), driven over CDP
real-clients/summarize.py                                        # the table, from the records
real-clients/refusal-causes.py lab/.runtime/real-clients/runs/*  # each stock refusal with its server-log reason
real-clients/doc-probe.sh                                        # the Zed and Amp documents
```

Records go to `lab/.runtime/real-clients/runs/` (not committed). The test user (`alice` / `alice-lab-only`) is lab-only.
