| client | Keycloak | challenge | client_id used | DCR POST | authorize outcome(s) | tokens issued | Keycloak errors | MCP calls with valid token | net timeouts in log | run |
|---|---|---|---|---|---|---|---|---|---|---|
| codex | stock | - | https://chatgpt.com/oauth/codex/client.json | - | refused_at_authorize(Client Metadata fetch failed); refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T123455Z-codex-stock |
| codex | stock | scope hint | https://chatgpt.com/oauth/codex/client.json | - | refused_at_authorize(Client Metadata fetch failed); refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T123937Z-codex-stock-scoped |
| codex | ext | - | https://chatgpt.com/oauth/codex/client.json | - | error_redirect:invalid_scope(Invalid scopes: openid phone service_account profile roles acr offlin; code_delivered_to_client | 1 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T124419Z-codex-ext |
| codex | ext | scope hint | https://chatgpt.com/oauth/codex/client.json | - | error_redirect:invalid_scope(Invalid scopes: openid service_account offline_access email roles org; code_delivered_to_client | 1 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T124435Z-codex-ext-scoped |
| goose | stock | - | https://goose-docs.ai/oauth/client-metadata.json | - | refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T124451Z-goose-stock |
| goose | stock | scope hint | https://goose-docs.ai/oauth/client-metadata.json | - | refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T124733Z-goose-stock-scoped |
| goose | ext | - | https://goose-docs.ai/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,server/discover,tools/call,tools/list | 0 | 20261017T125015Z-goose-ext |
| goose | ext | scope hint | https://goose-docs.ai/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,server/discover,tools/call,tools/list | 0 | 20261017T125107Z-goose-ext-scoped |
| hermes | stock | - | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261017T125144Z-hermes-stock |
| hermes | stock | scope hint | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261017T125207Z-hermes-stock-scoped |
| hermes | ext | - | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261017T125227Z-hermes-ext |
| hermes | ext | scope hint | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261017T125248Z-hermes-ext-scoped |
| opencode | stock | - | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261017T125316Z-opencode-stock |
| opencode | stock | scope hint | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261017T125336Z-opencode-stock-scoped |
| opencode | ext | - | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261017T125353Z-opencode-ext |
| opencode | ext | scope hint | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261017T125409Z-opencode-ext-scoped |
| opencode19 | stock | - | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261017T125424Z-opencode19-stock |
| opencode19 | stock | scope hint | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261017T125440Z-opencode19-stock-scoped |
| opencode19 | ext | - | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261017T125456Z-opencode19-ext |
| opencode19 | ext | scope hint | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261017T125512Z-opencode19-ext-scoped |
| opencodedev | stock | - | https://opencode.ai/oauth/opencode/client.json | - | refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T125527Z-opencodedev-stock |
| opencodedev | stock | scope hint | https://opencode.ai/oauth/opencode/client.json | - | refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261017T125816Z-opencodedev-stock-scoped |
| opencodedev | ext | - | https://opencode.ai/oauth/opencode/client.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261017T130103Z-opencodedev-ext |
| opencodedev | ext | scope hint | https://opencode.ai/oauth/opencode/client.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261017T130127Z-opencodedev-ext-scoped |
| mcpremote | stock | - | - | 403 | no browser opened | 0 | - | - | 0 | 20261017T130153Z-mcpremote-stock |
| mcpremote | stock | scope hint | - | 403 | no browser opened | 0 | - | - | 0 | 20261017T130219Z-mcpremote-stock-scoped |
| mcpremote | ext | - | - | 403 | no browser opened | 0 | - | - | 0 | 20261017T130235Z-mcpremote-ext |
| mcpremote | ext | scope hint | - | 403 | no browser opened | 0 | - | - | 0 | 20261017T130259Z-mcpremote-ext-scoped |
