#!/usr/bin/env bash
# Shared by demo/act*.sh. Sourced, not run. Every request goes to the lab live (scripts/lab.sh, Keycloak 26.8.0) through
# scripts/common.sh, the same functions the checks use; each refusal's reason is read from that request's server log
# window. Labels and explanations are scripted; outcomes are not.
#
#   PRESENT=1   wait for a key before every step (live talk); otherwise steps advance after PAUSE seconds
#   PAUSE=1.2   seconds between steps when not presenting
set -uo pipefail
DEMO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ROOT=$(cd "$DEMO/.." && pwd); RT=$ROOT/lab/.runtime
V=${DEMO_VERSION:-26.8.0}; PORT_BASE=${PORT_BASE:-18100}
# the lab's own readiness and ownership gate; it also says where the metadata server is
LAB_STATUS=$(cd "$ROOT" && VERSIONS=$V PORT_BASE=$PORT_BASE scripts/lab.sh status 2>&1) || {
  printf '%s\n' "$LAB_STATUS"; echo "lab not ready: VERSIONS=$V scripts/lab.sh build install"; exit 77; }
export MD=$(awk '$1=="metadata"{print $2}' <<<"$LAB_STATUS") SCENARIOS=$RT/scenarios
export KC_STOCK=http://127.0.0.2:$PORT_BASE KC_EXT=http://127.0.0.2:$((PORT_BASE+1))
export C_STOCK=cimdlab-stock-$V C_EXT=cimdlab-ext-$V ADMIN_PASSWORD_FILE=$RT/admin-password
. "$ROOT/scripts/common.sh"

PAUSE=${PAUSE:-1.2}; PRESENT=${PRESENT:-0}
B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
wait_key(){ if [ "$PRESENT" = 1 ] && [ -r /dev/tty ]; then printf '%s  ⏎%s' "$D" "$N"; read -rsn1 _ </dev/tty; printf '\r   \r'; else sleep "$PAUSE"; fi; }
title(){ printf '\n%s%s%s\n%s\n' "$B" "$*" "$N" "${D}$(printf '%.0s─' $(seq 1 84))${N}"; wait_key; }
step(){ printf '\n%s▸ %s%s\n' "$C" "$*" "$N"; wait_key; }
note(){ printf '  %s%s%s\n' "$D" "$*" "$N"; }
short(){ printf '%s' "${1#https://}"; }

# display names for the eight documents of scripts/common.sh (VENDOR_DOCS, fetched live on every run)
declare -A NAME=([openai-chatgpt]="OpenAI (ChatGPT)" [openai-codex]="OpenAI (Codex)" [openai-atlas]="OpenAI (Atlas)"
  [opencode]=opencode [vscode]="VS Code" [copilot-cli]="GitHub Copilot CLI" [hermes-agent]="Hermes Agent" [goose]=goose)
ORDER=(openai-chatgpt openai-codex openai-atlas opencode goose vscode copilot-cli hermes-agent)

verdict(){ case "$(outcome)" in accepted) printf '%saccepted%s' "$G" "$N";; refused) printf '%srefused %s' "$R" "$N";;
  network) printf '%sNETWORK %s' "$R" "$N";; *) printf '%sERROR   %s' "$R" "$N";; esac; }
reason(){ # the server's own reason for the last auth(), in words
  case "$CAUSE" in -) ;; PARSE:*) printf 'parse: unknown property "%s"' "${CAUSE#PARSE:}";;
    DOMAIN:*) printf 'untrusted URI host %s' "${CAUSE#DOMAIN:}";; CLIENT_ID_MISSING) printf 'client_id missing';;
    CLIENT_ID_MISMATCH) printf 'client_id does not match the URL';; REDIRECT_MISMATCH) printf 'redirect_uri not in redirect_uris';;
    MALFORMED_JSON) printf 'malformed JSON';; NETWORK) printf 'fetch did not complete (network): not a result';; *) printf '%s' "$CAUSE";; esac; }
cimd_say(){ local n; n=$(cimd_count "$1") || { echo "?"; return; }; printf '%s' "$n"; }
