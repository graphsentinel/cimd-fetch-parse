# Fetch Succeeded, Parse Failed

**Published MCP client identities (CIMD) against Keycloak.** Which published client identities stock Keycloak accepts,
why the rest are refused, which extension point can reach the refusal, and what a narrow change costs in validation
coverage — as eleven checks you can run against a lab on your own machine.

An MCP client can publish its identity as a URL: a Client ID Metadata Document (CIMD). The authorization server fetches
the document, parses it into a client, validates it and stores the client. Keycloak supports this as an experimental
feature (`--features=cimd`) together with a realm client policy.

## What was measured

Eight CIMD documents published by their vendors (checks 01–10), fetched live and **sent to Keycloak by the lab itself**
(not by the client programs), against Keycloak **26.7.0 and 26.8.0** (each version separately, every run the summary
counted; see [evidence/](evidence/)). What the client
programs themselves do is a separate measurement, in the next table.

| Published document | Stock Keycloak | Refused on (server log) | Document with the `lenient-cimd` executor | Its client program (next table) |
|---|---|---|---|---|
| OpenAI (ChatGPT) `chatgpt.com/oauth/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted | not tested (hosted service) |
| OpenAI (Codex) `chatgpt.com/oauth/codex/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted | Codex CLI uses it |
| OpenAI (Atlas) `chatgpt.com/oauth/atlas/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted | not tested (hosted service) |
| opencode `opencode.ai/oauth/opencode/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted | the tested releases (1.2.27, 1.19.3) do **not** use it; the development build does |
| goose `goose-docs.ai/oauth/client-metadata.json` | refused | `code_challenge_methods_supported` | accepted with `[::1]` in the allowlist | goose uses it |
| VS Code `vscode.dev/oauth/client-metadata.json` | accepted | — | accepted | not measured end to end |
| GitHub Copilot CLI `github.com/copilot/cli/client-metadata.json` | accepted | — | accepted | Copilot CLI uses it |
| Hermes Agent `nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json` | accepted | — | accepted | Hermes uses it |

Two more published documents found later, Zed's and Amp's, carry no extra property and are accepted by stock Keycloak
([evidence/real-clients/doc-probe/](evidence/real-clients/doc-probe/); Zed's real loopback redirect with a port too).

**The client programs** ([real-clients/](real-clients/)): each program pointed at an OAuth-protected MCP server behind
Keycloak 26.8.0 with **anonymous registration locked**; logins by a real headless Chromium (Playwright), Copilot CLI by a
person; outcomes from Keycloak's events and server log and the MCP server's log, not from the programs' messages.

| Client program | How it registers | Stock Keycloak | With the `lenient-cimd` executor |
|---|---|---|---|
| GitHub Copilot CLI 1.0.98 | its CIMD URL | token, tools listed | token, tools listed |
| Hermes Agent 0.22.2 | its CIMD URL | token, tools listed | token, tools listed |
| goose 1.55.0 | its CIMD URL | **refused at parse time** (`code_challenge_methods_supported`) | token, a tool called |
| Codex CLI 0.153.4 | its CIMD URL | **refused at parse time** (`token_endpoint_auth_methods_supported`) | token, after its own fallback from Keycloak's full scope list to fewer scopes; no authenticated MCP call measured |
| opencode development build (default branch `dev`, a49f179, unreleased; CIMD is in no release as of 17 Oct 2026) | its CIMD URL | **refused at parse time** (`token_endpoint_auth_methods_supported`) | token, tools listed |
| opencode 1.2.27 | dynamic registration | 403, registration locked | 403 |
| opencode 1.19.3 (latest release) | dynamic registration | 403, registration locked | 403 |
| mcp-remote 0.15.1 (its defaults) | dynamic registration | 403, registration locked | 403 |
| VS Code 1.140 | — | reached the MCP server and found Keycloak; its sign-in did not start under automation: not measured | — |

With registration locked, **6 of the 8 client builds measured end to end obtained no token from stock Keycloak**
(VS Code, not measured end to end, is not counted). Three were refused at parse time on their published CIMD document;
all three obtained a token once unknown properties were tolerated, and goose and the opencode development build also made
authenticated MCP calls. The other three (two opencode releases, mcp-remote) used dynamic registration, which locked
registration refuses with either executor.

- **Five of the eight published documents we tested** (three vendors: OpenAI, opencode, goose) are refused by stock Keycloak, each
  on one of **two extra properties**. RFC 7591 §2, which the CIMD draft builds on, says an authorization server MUST
  ignore client metadata it does not understand.
- **The fetch succeeded; the parse failed.** The caller is shown `Client Metadata fetch failed`; the server log for the
  same request says `HTTP connection failure: … UnrecognizedPropertyException: Unrecognized field "…"`.
- **Cause, both directions** (check 02): adding `token_endpoint_auth_methods_supported` to an accepted document makes it
  fail; removing it from a refused one makes it pass.
- **Where an extension can act** (check 03): a custom CIMD provider's `determineFetchOperation` receives only the
  client_id, before the fetch; `createClientMetadata`, its only method that receives the document, is never called when
  the parse fails. The executor's fetch-and-parse is where the document is.
- **One fetch-and-parse override** (`spi/`, executor `lenient-cimd`, one Jackson flag): all eight accepted and persisted
  as clients in one run (CIMD client rows 0 → 8, exactly the eight requested client_ids), with anonymous dynamic
  registration refused in the same realm (HTTP 403, Trusted Hosts policy) — check 10.
- **Five negative controls stay refused, each for its own reason** (check 04): malformed JSON, missing client_id,
  client_id not matching its URL, `redirect_uri` instead of `redirect_uris`, a foreign-domain `logo_uri`.
- **The override keeps the stock executor's other behaviour** (check 11): same Keycloak, stock executor vs `lenient-cimd`,
  clean documents. Our first version lost three stock behaviours — caching (two fetches instead of one), the
  public-client default for a document without `token_endpoint_auth_method` (stored as confidential), and 304 Not Modified
  on refresh (refused) — because it re-implemented the fetch without the stock method's update path, cache times and
  `augmentClientOIDC`. The current version follows the stock method and only parses leniently: check 11 PASS, checks
  01–10 10/10 PASS, the real clients unchanged ([evidence/executor-parity/](evidence/executor-parity/)).
- **The same documents against the upstream fix** ([evidence/upstream-pr51235/](evidence/upstream-pr51235/)): Keycloak
  26.8.0 with only keycloak PR #51235 applied (`scripts/upstream-pr.sh`) and `lenient-cimd` give the same outcome,
  status and caller message in all 28 rows (published documents, controls, edge documents, the check 11 cases), and
  goose, Codex CLI and opencode's development build get the same results with both.
- **The executor also checks a redirect host the request does not use** (check 09): goose lists an IPv4 and an IPv6
  loopback redirect; with IPv4 hosts only it is refused naming `[::1]`; `::1` does not help, `[::1]` does.

Reference runs of checks 01–10 ([evidence/](evidence/), raw requests and responses, server logs, summaries; made with the
first version of `lenient-cimd`, before the check 11 fix): clean Ubuntu 26.04 VM,
5 rounds on both versions, 100/100 checks PASS; clean Ubuntu 24.04 VM, 20/20; each followed by a reinstall round (20/20)
and an uninstall. Keycloak 26.8.1, measured separately (3 rounds, 30/30), gives the same results.

## Not claimed

- **Not a discovery.** The parse defect is reported upstream: [keycloak#51039](https://github.com/keycloak/keycloak/issues/51039)
  by ryotaro612 (the ChatGPT document, closed), [keycloak#51236](https://github.com/keycloak/keycloak/issues/51236) and
  the open PR [keycloak#51235](https://github.com/keycloak/keycloak/pull/51235) by achetronic, and
  [keycloak#53363](https://github.com/keycloak/keycloak/issues/53363) by antoniocasagrande-airia for the registration
  endpoint (status as of 2026-10-17). This repository adds
  the measured matrix, the single-variable cause, the extension point and a bounded regression set. The same parser
  change was also written as downstream executors by others: Lukas Chripko (described in a comment on PR #51235) and
  MemoryOS ([kl3inIT/MemoryOS#436](https://github.com/kl3inIT/MemoryOS/pull/436)).
- **Not a fix.** `lenient-cimd` is an experiment on an internal SPI; remove it when upstream resolves the issue. Its five
  negative controls and the three stock behaviours of check 11 are bounded coverage, not proof that nothing else changed.
- Eight documents in the checks (plus two probed later) are not an ecosystem ratio. The checks stop at the login page (acceptance =
  the authorization request is answered with the login page, not an error; check 10 also reads the stored clients); token
  issuance is outside them; the client-program table measures it for eight client builds. Those are not an ecosystem
  ratio either: ChatGPT and Atlas are hosted (not testable against a local server), VS Code was not measured
  end to end, other clients were not tried. Authenticated dynamic registration was not tested. Which registration a
  client chooses was measured only for those builds (check 07: every realm we tested advertises CIMD).
- The vendor documents are fetched live and may change; the results are dated by their run.

## Quickstart (Ubuntu 24.04 or 26.04)

```bash
git clone https://github.com/graphsentinel/cimd-fetch-parse.git && cd cimd-fetch-parse
scripts/platform.sh install      # only what is missing: podman, jq, curl, python3, openssl, iproute2
scripts/lab.sh all               # build the extension, start the lab, run every check 3x on 26.7.0 and 26.8.0
scripts/lab.sh uninstall         # removes only this lab's containers and processes
```

`lab.sh all` ends with a table (also in `lab/.runtime/summary.md`) and exits non-zero unless every planned check passed,
its selected fields have the expected values (`lab/expected.tsv`) and its requests match the proxy's raw record. It needs internet access (vendor documents, `nip.io`, images) and about
6 GB of memory for two versions.

The demo (four acts, live against the lab; act 4 a real agent, goose): `VERSIONS=26.8.0 scripts/lab.sh build install`,
then `demo/run.sh` (`--present` for a talk). See [demo/](demo/).

## How it works

| Layer | Command | Does |
|---|---|---|
| 1 host | `scripts/platform.sh install` | installs missing Ubuntu packages only; leaves an existing Docker/Podman alone |
| 1 host | `scripts/platform.sh status` | tools present, container engine runs a container |
| 2 lab | `scripts/lab.sh build` | builds `spi/` for each Keycloak version (Maven in a container) |
| 2 lab | `scripts/lab.sh install` | per version three Keycloak containers on `127.0.0.1` (stock · with this extension · CIMD off), a recording proxy in front of each on `127.0.0.2`, a local HTTPS metadata server with a generated lab CA |
| 2 lab | `scripts/lab.sh status` | readiness gate (every Keycloak answers through its proxy with the expected version) |
| 2 lab | `scripts/lab.sh test` | writes the plan, runs every check `RUNS` times per version, keeps raw evidence per run, then `summary` |
| 2 lab | `scripts/lab.sh summary` | fail-closed: plan complete, every check PASS (only `NOT RUN [vendor-fetch]` may precede a PASS), selected fields = `lab/expected.tsv`, every authorization / registration request the check saw = the proxy's raw record (same order, same status) |
| 2 lab | `scripts/lab.sh uninstall` / `reinstall` | removes only this checkout's containers (labels `cimdlab=1`, `cimdlab.root=<checkout>`) and the processes in its pidfiles whose command line is its own script |

Options (environment): `VERSIONS` (`26.7.0 26.8.0`), `RUNS` (3), `CHECKS` (`01 … 10`), `ENGINE` (`podman`/`docker`,
auto), `PORT_BASE` (18100; Keycloak ports 18100–18102, 18110–18112, …), `MD_HOST` (default: this host's IPv4 with dashes
+ `.nip.io`), `ATTEMPTS` (3).

**Checks** (`checks/`, each exits 0 PASS · 1 FAIL · 77 NOT RUN):

| # | Check | Server |
|---|---|---|
| 01 | stock compatibility of the eight documents, refusal reason from the server log | stock |
| 02 | single-variable causality (copies on the local metadata server) | stock |
| 03 | provider hook: `determineFetchOperation` vs `createClientMetadata` on accepted / refused | extension (`logging-cimd` provider) |
| 04 | two positive and five negative controls, each with its expected reason | extension (`lenient-cimd`) |
| 05 | the eight documents with `lenient-cimd`, IPv4/name allowlist | extension |
| 06 | default realm: CIMD refused at parse time and anonymous registration refused | stock |
| 07 | discovery advertisement vs the feature flag; DCR open, CIMD refused for different reasons | extension + CIMD off |
| 08 | anonymous registration locked: stock 3/8 vs `lenient-cimd` 7/8 | extension |
| 09 | goose: IPv4-only 400 → `::1` 400 → `[::1]` 200 | extension |
| 10 | all eight accepted and persisted in one run, anonymous registration refused (403) | extension |
| 11 | `lenient-cimd` vs the stock executor: caching, public-client default, 304 on refresh (waits 305 s) | extension |

**Why a check can end NOT RUN.** The reason for every CIMD refusal is taken from the Keycloak server log of the
container that answered, bounded to that request (registration policy names and caller messages come from the response
body). A vendor document that Keycloak could not fetch (`java.net…` in that request's log) is not a result: the check
ends `NOT RUN [vendor-fetch]` (77) and `lab.sh test` tries it again (`ATTEMPTS`); every attempt is kept on disk.
A contradiction is reported first: if any request already contradicts the claim the check is a FAIL, whatever else
could not be fetched. Missing setup (realm, policy, allowlist not read back as written) is a final NOT RUN.

**Raw evidence** (`lab/.runtime/runs/<run>/`): `requests.jsonl` (every request and raw response through the recording
proxy; request headers, request bodies and token responses are not written, secret fields in responses are redacted),
`server-*.log` (the three Keycloak logs for that window), `observed.jsonl` (each authorization / registration request as
the check saw it), `metadata-requests.jsonl`, `stdout.txt`, `manifest.json`
(check sha256, extension jar sha256, Keycloak image digest, exit code).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `port(s) in use by another service` | set `PORT_BASE` to a free range, or free port 8443 |
| a check ends `NOT RUN [vendor-fetch]` | Keycloak's first fetch to a vendor host can time out; `lab.sh test` retries; check your network if it persists |
| `lab not ready` | `podman logs cimdlab-stock-<version>`; the first start downloads images and can take minutes |
| `cannot determine this host's IPv4 address` | set `MD_HOST` to a name that resolves to this host (e.g. `10-0-0-5.nip.io`) |

## Versions

| Component | Version |
|---|---|
| Keycloak | 26.7.0 and 26.8.0 (measured, default), 26.8.1 (measured separately: `VERSIONS=26.8.1`); pinned by digest in `scripts/versions.env`; `scripts/check-versions.sh` reports newer releases |
| Extension | built against the Keycloak version it runs on (`-Dkeycloak.version`) |
| Build image | `maven:3.9-eclipse-temurin-17` (digest in `versions.env`) |

## Layout

```
demo/          the demo, live: four acts (see its README)
real-clients/  real agent clients against an MCP server behind the lab Keycloak (see its README)
checks/        the checks 01–11 (bash)            spi/          lenient-cimd executor, logging-cimd provider (Java)
scripts/       platform.sh, lab.sh, common.sh, recording-proxy.py, metadata-server.py, summary.py, tls.sh, …
lab/           expected.tsv (the expected value of every recorded field)
evidence/      raw evidence and summaries of the reference runs
```

The Keycloak bootstrap admin (`lab-admin`) gets a random password per checkout at install time
(`lab/.runtime/admin-password`, mode 0600, never printed); a Keycloak that accepts it is this lab's own, and `status`
and `lab.sh test` check before any request, and again before and after every attempt, that each lab port is held by
this checkout's container or process (an attempt that ends on a lab it no longer holds is not a result; the lab assumes
no other process takes its ports in between). TLS keys are
generated at install time under `lab/.runtime/tls/`. Nothing under `lab/.runtime/` is committed.

## License

Apache-2.0 — see [LICENSE](LICENSE).
