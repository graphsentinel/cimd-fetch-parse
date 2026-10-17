#!/usr/bin/env bash
# Installs goose 1.55.0 (the build measured in evidence/real-clients/) for act 4, from its GitHub release, checked
# against the release's published sha256. Target: $CLIENTS_DIR/goose-dl/goose (default lab/.runtime/real-clients/clients).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); CLIENTS=${CLIENTS_DIR:-$ROOT/lab/.runtime/real-clients/clients}
case "$(uname -m)" in
  x86_64)  A=x86_64-unknown-linux-gnu;  SUM=fd3932908328fac850ca7ad2a8289c744e0c2ddaf4c5a2338709fb17a00b3a4c;;
  aarch64) A=aarch64-unknown-linux-gnu; SUM=ea83f59bb165a3d999dd00edf69a58028747f31e404b96f0153452c6b1651188;;
  *) echo "no goose 1.55.0 Linux build for $(uname -m)" >&2; exit 1;;
esac
F=goose-$A.tar.gz; D=$CLIENTS/goose-dl; mkdir -p "$D"
[ -x "$D/goose" ] && "$D/goose" --version 2>/dev/null | grep -q '1\.55\.0' && { echo "goose 1.55.0 already at $D/goose"; exit 0; }
curl -fL --retry 3 -sS -o "$D/$F" "https://github.com/aaif-goose/goose/releases/download/v1.55.0/$F"
echo "$SUM  $D/$F" | sha256sum -c - || { rm -f "$D/$F"; exit 1; }
t=$(mktemp -d); tar -xzf "$D/$F" -C "$t"; install -m 0755 "$(find "$t" -type f -name goose | head -1)" "$D/goose"; rm -rf "$t"
"$D/goose" --version
