#!/usr/bin/env bash
# 02 · Is it really that property? A single-variable test in both directions, for token_endpoint_auth_methods_supported.
#
# Copies served by the local metadata server, client_id = the copy's own URL (client_uri and logo_uri removed, the
# redirect points at the metadata server, so the allowlist holds that one host):
#   a) the OpenAI (Codex) body, property present             -> parse refusal on the property expected
#   b) the same body, property removed                       -> acceptance expected
#   c) the Hermes body (accepted as published), property added -> parse refusal on the property expected
#   d) the Hermes body, untouched                             -> acceptance expected (positive control)
# A causality experiment on copies; it changes nothing for the real clients.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_STOCK; REALM=lab-causality; FIELD=token_endpoint_auth_methods_supported
refresh
curl -sk -o /dev/null --max-time 5 "$MD/_requests" || not_run "metadata server not reachable"
sub OA fetch_or_skip https://chatgpt.com/oauth/codex/client.json
sub HE fetch_or_skip https://nousresearch.github.io/hermes-agent/docs/oauth/client-metadata.json
[ "$(jq -r --arg a $FIELD 'has($a)' <<<"$OA")" = true ] || not_run "the OpenAI document no longer carries $FIELD"
[ "$(jq -r --arg a $FIELD 'has($a)' <<<"$HE")" = false ] || not_run "the Hermes document now carries $FIELD"
copy(){ # copy <name> <body> <keep|remove|add>
  local url="$MD/c/$1.json" j
  j=$(jq --arg u "$url" --arg r "$MD/p/redirect" '.client_id=$u | .redirect_uris=[$r] | del(.client_uri) | del(.logo_uri)' <<<"$2")
  case $3 in remove) j=$(jq "del(.$FIELD)" <<<"$j");; add) j=$(jq --arg a $FIELD '. + {($a): ["none"]}' <<<"$j");; esac
  printf '%s' "$j" > "$SCENARIOS/$1.json"; }
copy cause-a "$OA" keep; copy cause-b "$OA" remove; copy cause-c "$HE" add; copy cause-d "$HE" keep
realm_setup $REALM "[\"$(md_host)\"]"
for e in "cause-a|parse:$FIELD" "cause-b|accepted" "cause-c|parse:$FIELD" "cause-d|accepted"; do n=${e%%|*}
  auth $REALM "$MD/c/$n.json" "$MD/p/redirect" $C_STOCK
  expect "$n" "${e#*|}"
  printf '  %-8s %s present=%s  HTTP %s  %s %s\n' "$n" $FIELD "$(jq -r --arg a $FIELD 'has($a)' "$SCENARIOS/$n.json")" "$H" "$(outcome)" "$CAUSE"
  record "result:$n" "$(outcome)" "cause:$n" "$CAUSE"
done
settle
echo "PASS: present -> refused (parse), removed -> accepted, added -> refused (parse), untouched -> accepted."
