Copilot CLI, stock Keycloak, person in the loop (2026-10-17 00:04–00:06 UTC).
Keycloak side (proxy record, LOGIN + CODE_TO_TOKEN events) was captured by this run, which recreated the realm at 00:04:06.
This run's own MCP server could not bind :19000 (an earlier `manual.sh vscode stock` session still held it), so the
copilot-cli requests were served and logged by that session's server (same issuer, same fresh realm);
mcp-requests.jsonl here = the copilot-cli lines of ../../excluded/20261016T235548Z-vscode-stock-no-vscode-attempt/mcp-requests.jsonl.
