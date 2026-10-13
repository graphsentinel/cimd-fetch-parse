#!/usr/bin/env bash
# Layer 1: the host. install | status
#
# install: installs only what is missing, from Ubuntu's own packages (dpkg-query decides; nothing installed is
#   upgraded): podman (+ uidmap for rootless), jq, curl, python3, openssl, iproute2. An existing Docker or Podman
#   is left as it is; scripts/lab.sh uses podman when present, else docker (ENGINE overrides).
# status: what the lab needs, and whether the container engine runs a container.
set -euo pipefail
PKGS=(podman uidmap jq curl python3 openssl iproute2 ca-certificates)
missing(){ local p m=(); for p in "$@"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || m+=("$p"); done; echo "${m[@]}"; }

install(){
  [ "$(. /etc/os-release; echo "$ID")" = ubuntu ] || echo "warning: tested on Ubuntu 24.04 and 26.04 only" >&2
  local need; need=$(missing "${PKGS[@]}")
  if command -v docker >/dev/null && ! command -v podman >/dev/null; then need=$(printf '%s\n' $need | grep -vxE 'podman|uidmap' || true); fi
  if [ -n "$need" ]; then echo "installing: $need"; sudo apt-get update -qq; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $need >/dev/null
  else echo "nothing to install"; fi
  status
}

status(){
  local ok=0 t
  for t in jq curl python3 openssl ss; do command -v $t >/dev/null && echo "$t: $(command -v $t)" || { echo "$t: MISSING"; ok=1; }; done
  local e=${ENGINE:-}; [ -n "$e" ] || { command -v podman >/dev/null && e=podman || { command -v docker >/dev/null && e=docker; }; }
  if [ -z "$e" ]; then echo "container engine: MISSING"; return 1; fi
  echo "container engine: $e $("$e" --version 2>/dev/null | head -1)"
  "$e" run --rm docker.io/library/busybox:1.37 true >/dev/null 2>&1 && echo "$e: runs containers" || { echo "$e: cannot run a container"; ok=1; }
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' || { echo "python3 >= 3.10 required"; ok=1; }
  return $ok
}

case "${1:-status}" in install) install;; status) status;; *) echo "usage: $0 install|status" >&2; exit 2;; esac
