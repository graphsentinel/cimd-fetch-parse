#!/usr/bin/env bash
# Act 2: which extension point can reach the refusal, the CIMD provider hook or the executor? (same as checks/03)
. "$(dirname "$0")/lib.sh"
KC=$KC_EXT; REALM=demo-provider; refresh
grep -q 'cimd-provider-name=logging-cimd' <<<"$("$ENGINE" inspect --format '{{json .Config.Cmd}}' "$C_EXT" 2>/dev/null)" \
  || not_run "the logging-cimd provider is not selected on $C_EXT"

title "Act 2 · Keycloak $(server_version) with a logging CIMD provider · where does the provider see the document?"

ACC_URL=https://vscode.dev/oauth/client-metadata.json; REF_URL=https://chatgpt.com/oauth/codex/client.json
sub AJ fetch_or_skip $ACC_URL; sub RJ fetch_or_skip $REF_URL
realm_setup $REALM "$(json_array $(printf '%s\n%s\n' "$AJ" "$RJ" | uri_hosts))"
hooks(){ grep -cF "ENTRY $1 clientId=$2" <<<"$WINDOW" || true; }

step "The provider logs every call it receives. Two documents, stock executor:"
printf '  %-16s %-6s %-9s %-26s %-22s\n' "" "HTTP" "" "determineFetchOperation" "createClientMetadata"
for pair in "VS Code|$ACC_URL|$AJ" "OpenAI (Codex)|$REF_URL|$RJ"; do IFS='|' read -r n u j <<<"$pair"
  auth $REALM "$u" "$(jq -r '.redirect_uris[0]' <<<"$j")" $C_EXT
  printf '  %-16s %-6s %b  %-26s %-22s\n' "$n" "$H" "$(verdict)" "$(hooks determineFetchOperation "$u") call(s)" "$(hooks createClientMetadata "$u") call(s)"
  [ "$CAUSE" = - ] || note "server: $(reason)"
done

step "Reading"
note "determineFetchOperation receives only the client_id, before the fetch."
note "createClientMetadata, the provider's only method that receives the document, is not called when"
note "the parse fails. On this path the provider hook cannot reach the document; the executor's fetch-and-parse can."
wait_key
