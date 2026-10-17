| client | Keycloak | challenge | client_id used | DCR POST | authorize outcome(s) | tokens issued | Keycloak errors | MCP calls with valid token | net timeouts in log | run |
|---|---|---|---|---|---|---|---|---|---|---|
| codex | stock | - | https://chatgpt.com/oauth/codex/client.json | - | refused_at_authorize(Client Metadata fetch failed); refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261016T225814Z-codex-stock |
| codex | stock | scope hint | https://chatgpt.com/oauth/codex/client.json | - | refused_at_authorize(Client Metadata fetch failed); refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261016T230307Z-codex-stock-scoped |
| codex | ext | - | https://chatgpt.com/oauth/codex/client.json | - | error_redirect:invalid_scope(Invalid scopes: openid microprofile-jwt basic web-origins organizatio; code_delivered_to_client | 1 | LOGIN_ERROR:invalid_request | - | 0 | 20261016T230750Z-codex-ext |
| codex | ext | scope hint | https://chatgpt.com/oauth/codex/client.json | - | error_redirect:invalid_scope(Invalid scopes: openid acr web-origins email profile offline_access r; code_delivered_to_client | 1 | LOGIN_ERROR:invalid_request | - | 0 | 20261016T230803Z-codex-ext-scoped |
| opencode | stock | - | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261016T230817Z-opencode-stock |
| opencode | stock | scope hint | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261016T230832Z-opencode-stock-scoped |
| opencode | ext | - | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261016T230848Z-opencode-ext |
| opencode | ext | scope hint | - | 403,403 | no browser opened | 0 | - | - | 0 | 20261016T230903Z-opencode-ext-scoped |
| goose | stock | - | https://goose-docs.ai/oauth/client-metadata.json | - | refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261016T230917Z-goose-stock |
| goose | stock | scope hint | https://goose-docs.ai/oauth/client-metadata.json | - | refused_at_authorize(Client Metadata fetch failed) | 0 | LOGIN_ERROR:invalid_request | - | 0 | 20261016T231430Z-goose-stock-scoped |
| goose | ext | - | https://goose-docs.ai/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,server/discover,tools/call,tools/list | 0 | 20261016T231952Z-goose-ext |
| goose | ext | scope hint | https://goose-docs.ai/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,server/discover,tools/call,tools/list | 0 | 20261016T232352Z-goose-ext-scoped |
| hermes | stock | - | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261016T232642Z-hermes-stock |
| hermes | stock | scope hint | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261016T232702Z-hermes-stock-scoped |
| hermes | ext | - | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261016T232723Z-hermes-ext |
| hermes | ext | scope hint | https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json | - | code_delivered_to_client | 1 | - | initialize,notifications/initialized,tools/list | 0 | 20261016T232743Z-hermes-ext-scoped |
| opencode19 | stock | - | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261016T232802Z-opencode19-stock |
| opencode19 | stock | scope hint | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261016T232818Z-opencode19-stock-scoped |
| opencode19 | ext | - | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261016T232835Z-opencode19-ext |
| opencode19 | ext | scope hint | - | 403,403,403 | no browser opened | 0 | - | - | 0 | 20261016T232852Z-opencode19-ext-scoped |
| copilot | stock | - | https://github.com/copilot/cli/client-metadata.json | - | person: copilot cli: authorization successful, tools listed; vscode never connected | 1 | - | initialize,notifications/initialized,ping,server/discover,tools/list | 0 | 20261017T000406Z-copilot-stock |
| copilot | ext | - | https://github.com/copilot/cli/client-metadata.json | - | person: (note not entered by the person; evidence: proxy record, Keycloak events, MCP lo | 1 | - | initialize,notifications/initialized,ping,server/discover,tools/list | 0 | 20261017T000735Z-copilot-ext |
| copilot | ext | - | https://github.com/copilot/cli/client-metadata.json | - | person: copilot ext: authenticated; first reconnect used cached old token (401), then co | 1 | - | initialize,notifications/initialized,ping,server/discover,tools/list | 0 | 20261017T000928Z-copilot-ext |
