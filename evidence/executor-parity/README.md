# Evidence: lenient-cimd against the stock executor (17 Oct 2026, Keycloak 26.8.0)

[checks/11-executor-parity.sh](../../checks/11-executor-parity.sh) runs both executors on the same Keycloak (the ext
container, where both are installed), each in its own realm, with the same clean documents from the local metadata
server, so the stock parser accepts them too and any difference is the override's.

| Case | Stock executor | lenient-cimd, first version (jar `c5f47188…`) | lenient-cimd, fixed (jar `8970ce78…`) |
|---|---|---|---|
| `cache`: document sent with `Cache-Control: max-age=3600`, two authorization requests | 1 fetch | **2 fetches** (no caching) | 1 fetch |
| `noauth`: document without `token_endpoint_auth_method` | public client, `none` | **confidential client, `client-secret`** | public client, `none` |
| `304`: after the cached copy expired (305 s wait), the publisher answers 304 Not Modified | accepted | **refused, HTTP 400** | accepted |

The first version overrode `fetchClientMetadata` without the stock method's update path (304 handling), passed `0, 0`
as the minimum and maximum cache times instead of the configured ones, and did not call `augmentClientOIDC`. The fixed
version follows the stock method (identical in 26.7.0 and 26.8.0) and only parses the body with the lenient mapper;
a body that cannot be parsed is reported as "Invalid Client Metadata: cannot be parsed as a client metadata document."
(the text of keycloak PR #51235).

- `runs/20261017T180557Z-before-fix/`: first version, check 11 FAIL on all three cases.
- `runs/20261017T181232Z-after-fix/`: fixed version, check 11 PASS.
- `checks-01-10-with-fix/`: checks 01–10 with the fixed version, one run each, 10/10 PASS (`summary.md`, per-run
  `stdout.txt` and `manifest.json`; the jar's sha256 is in each manifest).
- `real-clients-with-fix/`: goose 1.55.0, Codex CLI and opencode's development build against the fixed version
  ([real-clients/run.sh](../../real-clients/run.sh), `ext`): goose and opencode obtain a token and make MCP calls with
  it (goose `tools/call`, opencode `tools/list`), Codex CLI obtains a token; the same outcomes as with the first version.
  The clients' own HOME directories (their configuration and stored tokens) are not included.
- `excluded/20261017T175915Z-old-metadata-server/`: not counted. The metadata server still running was the version
  before response headers and status codes were supported, so no `Cache-Control` header and no 304 were sent (its
  `304` row is not a measurement of 304 handling).

In these copies the metadata server's host name, derived from the lab host's address, is replaced by `md-host`, and
the checkout path by `<checkout>`. Nothing else is changed.
