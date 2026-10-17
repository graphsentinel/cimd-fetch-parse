# Evidence: Keycloak 26.8.0 + keycloak PR #51235, next to stock and lenient-cimd (17 Oct 2026)

[keycloak#51235](https://github.com/keycloak/keycloak/pull/51235) (achetronic, open) makes the stock CIMD executor parse
documents with unknown properties ignored. Here its change under `services/src/main/java` (one file, +32 −2, PR head
`ad0cdc5`) is applied to the 26.8.0 release tag and only `keycloak-services` is rebuilt, with JDK 17 like the release.
Compared with the jar in the pinned 26.8.0 image, every file of the rebuilt jar is identical except the classes compiled
from that one file; the image is the pinned 26.8.0 image with that jar replaced
([scripts/upstream-pr.sh](../../scripts/upstream-pr.sh)). So the only difference from stock 26.8.0 is the PR. The
comparison below ran on a jar built by hand with the same steps (sha256 `39d9a1fe…`), before the script existed; the
script's own build (`5dc4002f…`; jars carry build timestamps) passes the same file-by-file check.

[checks/compare-upstream-pr.sh](../../checks/compare-upstream-pr.sh) then sends the same documents to three servers:
stock 26.8.0 (stock executor), the lab's ext server (this repository's `lenient-cimd`), and 26.8.0 + PR (stock executor).
Each cell: outcome, HTTP status, and the message the caller is shown (the server's logged reason is in `comparison.tsv`).

**Result: `lenient-cimd` and the PR give the same outcome, status and caller message in all 28 rows.** Both differ from
stock exactly where stock refuses a document over an unknown property, and both show "Invalid Client Metadata: cannot be
parsed as a client metadata document." where stock shows "Client Metadata fetch failed" for a body that cannot be
parsed (stock's log line for those also reads "HTTP connection failure", a JSON error reported as a network one).

| Document | Kind | Stock 26.8.0 | `lenient-cimd` | 26.8.0 + PR #51235 |
|---|---|---|---|---|
| `anonymous-registration` | realm: anonymous registration | refused (403) | refused (403) | refused (403) |
| `openai-chatgpt` | published | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `openai-codex` | published | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `openai-atlas` | published | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `opencode` | published | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `vscode` | published | accepted (200) | accepted (200) | accepted (200) |
| `copilot-cli` | published | accepted (200) | accepted (200) | accepted (200) |
| `hermes-agent` | published | accepted (200) | accepted (200) | accepted (200) |
| `goose` | published | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `clean` | control | accepted (200) | accepted (200) | accepted (200) |
| `unknown` | control: + unknown property | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `badjson` | control: malformed JSON | refused (400): “Client Metadata fetch failed” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” |
| `noid` | control: no client_id | refused (400): “Invalid Client Metadata: no client_id.” | refused (400): “Invalid Client Metadata: no client_id.” | refused (400): “Invalid Client Metadata: no client_id.” |
| `otherid` | control: client_id ≠ URL | refused (400): “Invalid Client Metadata: client_id property does…” | refused (400): “Invalid Client Metadata: client_id property does…” | refused (400): “Invalid Client Metadata: client_id property does…” |
| `typo` | control: `redirect_uri` for `redirect_uris` | refused (400): “Client Metadata fetch failed” | refused (400): “Invalid Client Metadata: redirect_uri parameter …” | refused (400): “Invalid Client Metadata: redirect_uri parameter …” |
| `foreign` | control: foreign-domain `logo_uri` | refused (400): “Invalid Client ID: domain not allowed.” | refused (400): “Invalid Client ID: domain not allowed.” | refused (400): “Invalid Client ID: domain not allowed.” |
| `redirstr` | edge: `redirect_uris` as one string | refused (400): “Client Metadata fetch failed” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” |
| `nullunk` | edge: unknown property = null | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `nested` | edge: unknown property, nested object | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `dupkey` | edge: duplicate key (`client_name` twice) | accepted (200) | accepted (200) | accepted (200) |
| `dupkey-stored-name` | edge: which value was stored | name `lab` | name `lab` | name `lab` |
| `empty` | edge: empty body | refused (400): “Client Metadata fetch failed” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” |
| `array` | edge: document wrapped in an array | refused (400): “Client Metadata fetch failed” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” | refused (400): “Invalid Client Metadata: cannot be parsed as a c…” |
| `unknownbig` | edge: unknown property, document 4.6 kB | refused (400): “Client Metadata fetch failed” | accepted (200) | accepted (200) |
| `unknownover` | edge: document over the 5,000-byte limit | refused (400): “Client Metadata fetch failed” | refused (400): “Client Metadata fetch failed” | refused (400): “Client Metadata fetch failed” |
| `cache-two-requests` | check 11: two requests, `max-age=3600` | accepted, fetches=1 | accepted, fetches=1 | accepted, fetches=1 |
| `noauth-client` | check 11: no `token_endpoint_auth_method` | accepted, {"public":true,"auth":"none"} | accepted, {"public":true,"auth":"none"} | accepted, {"public":true,"auth":"none"} |
| `304-on-refresh` | check 11: 304 after the cache expired | accepted (200) | accepted (200) | accepted (200) |

Notes on the table:

- The logged reasons differ only in wording: the PR logs "failed to parse client metadata document: <message>", so this
  repository's log reader (`cause` in `scripts/common.sh`) classifies those rows as `UNKNOWN`; `lenient-cimd` names the
  exception (`JsonParseException`), so they read `MALFORMED_JSON`. Outcome and caller message are the same.
- `unknownover`: all three refuse a document above the default 5,000-byte limit with "Client Metadata fetch failed";
  the log says why ("Response is at least 5476 bytes in size, with max bytes to be consumed being 5000"). The eight
  published documents are 409–841 bytes.
- `dupkey`: Jackson keeps the last value; all three stored `lab`.

## Real clients against 26.8.0 + PR (`real-clients/`, server `pr`)

| Client | Events | MCP calls with a valid token |
|---|---|---|
| goose 1.55.0 | `LOGIN`, `CODE_TO_TOKEN` | `initialize`, `tools/list`, `tools/call` |
| Codex CLI | `LOGIN`, `CODE_TO_TOKEN`, one `LOGIN_ERROR` `invalid_request` (Codex's own scope retry; the same with `lenient-cimd`) | none (as with `lenient-cimd`) |
| opencode development build | `LOGIN`, `CODE_TO_TOKEN` | `initialize`, `tools/list` |

The same results as with `lenient-cimd` (`real-clients/20261017T193742Z-opencodedev-ext/` was run in the same session
for that comparison; goose and Codex with `lenient-cimd`: [../executor-parity/real-clients-with-fix/](../executor-parity/real-clients-with-fix/)).
The clients' HOME directories are not included.

`excluded/20261017T193351Z-opencodedev-pr/`: not counted. `real-clients/run.sh` captured the login URL with a pattern
fixed to ports 18100/18101, so the URL on 18103 was never opened ("Waiting for authorization…"); the pattern now uses
the server's port and the attempt was repeated.

In these copies the metadata server's host name is replaced by `md-host` and the checkout path by `<checkout>`.
