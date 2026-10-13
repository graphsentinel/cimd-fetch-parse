# Fetch Succeeded, Parse Failed

**Published MCP client identities (CIMD) against Keycloak.** Which published client identities stock Keycloak accepts,
why the rest are refused, which extension point can reach the refusal, and what a narrow change costs in validation
coverage — as ten checks you can run against a lab on your own machine.

An MCP client can publish its identity as a URL: a Client ID Metadata Document (CIMD). The authorization server fetches
the document, parses it into a client, validates it and stores the client. Keycloak supports this as an experimental
feature (`--features=cimd`) together with a realm client policy.

## What was measured

Eight CIMD documents published by their vendors, fetched live, against Keycloak **26.7.0 and 26.8.0** (each version
separately, every valid run):

| Identity | Published at | Stock Keycloak | Refused on (server log) | With the `lenient-cimd` executor |
|---|---|---|---|---|
| OpenAI (ChatGPT) | `chatgpt.com/oauth/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted |
| OpenAI (Codex) | `chatgpt.com/oauth/codex/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted |
| OpenAI (Atlas) | `chatgpt.com/oauth/atlas/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted |
| opencode | `opencode.ai/oauth/opencode/client.json` | refused | `token_endpoint_auth_methods_supported` | accepted |
| goose | `goose-docs.ai/oauth/client-metadata.json` | refused | `code_challenge_methods_supported` | accepted with `[::1]` in the allowlist |
| VS Code | `vscode.dev/oauth/client-metadata.json` | accepted | — | accepted |
| GitHub Copilot CLI | `github.com/copilot/cli/client-metadata.json` | accepted | — | accepted |
| Hermes Agent | `nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json` | accepted | — | accepted |

- **Five of the eight identities we tested** (three vendors: OpenAI, opencode, goose) are refused by stock Keycloak, each
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
- **The executor also checks a redirect host the request does not use** (check 09): goose lists an IPv4 and an IPv6
  loopback redirect; with IPv4 hosts only it is refused naming `[::1]`; `::1` does not help, `[::1]` does.

Results of the reference run: [evidence/](evidence/) (raw requests and responses, server logs, the summary).

## Not claimed

- **Not a discovery.** The parse defect is reported upstream: [keycloak#51039](https://github.com/keycloak/keycloak/issues/51039)
  by ryotaro612 (the ChatGPT document, closed), [keycloak#51236](https://github.com/keycloak/keycloak/issues/51236) and
  the open PR [keycloak#51235](https://github.com/keycloak/keycloak/pull/51235) by achetronic, and
  [keycloak#53363](https://github.com/keycloak/keycloak/issues/53363) by antoniocasagrande-airia for the registration
  endpoint (status as of 2026-10-13). This repository adds
  the measured matrix, the single-variable cause, the extension point and a bounded regression set.
- **Not a fix.** `lenient-cimd` is an experiment on an internal SPI; remove it when upstream resolves the issue. Its five
  negative controls are bounded coverage, not proof that nothing else changed.
- Eight tested documents are not an ecosystem ratio. Token issuance / a completed login was not measured (acceptance =
  the authorization request is answered with the login page, not an error; check 10 also reads the stored clients). Authenticated dynamic registration was not tested.
  Whether a client switches to CIMD because a server advertises it (check 07: every realm we tested advertises it) was not
  measured.
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
| Keycloak | 26.7.0 and 26.8.0 (measured), pinned by digest in `scripts/versions.env`; `scripts/check-versions.sh` reports newer releases |
| Extension | built against the Keycloak version it runs on (`-Dkeycloak.version`) |
| Build image | `maven:3.9-eclipse-temurin-17` (digest in `versions.env`) |

## Layout

```
checks/        the ten checks (bash)            spi/          lenient-cimd executor, logging-cimd provider (Java)
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
