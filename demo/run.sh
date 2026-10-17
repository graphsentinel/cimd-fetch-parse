#!/usr/bin/env bash
# The demo, live: demo/run.sh [--present] [act ...]     (default: 1 2 3 4; act 4 is skipped when goose or its model is missing)
#   --present   wait for a key at every step and clear the screen between acts (for a talk)
#   WARM=0      skip the warm-up (run demo/warm.sh shortly before the talk instead; it takes about 1.5 minutes)
# Every act sends real requests to the lab; nothing is replayed. Before a talk: VERSIONS=26.8.0 scripts/lab.sh status
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd)
[ "${1:-}" = --present ] && { export PRESENT=1; shift; }
ACTS=("$@"); [ ${#ACTS[@]} -gt 0 ] || ACTS=(1 2 3 4)
if [ "${WARM:-1}" != 0 ]; then echo "warming up (first fetch of each document)…"; "$D/warm.sh" >/dev/null 2>&1 || { "$D/warm.sh"; exit 77; }; fi
for a in "${ACTS[@]}"; do
  [ "${PRESENT:-0}" = 1 ] && clear
  "$D/act$a.sh"; rc=$?
  if [ $rc = 77 ] && [ "$a" = 4 ] && [ $# -eq 0 ]; then echo "(act 4 skipped: see the NOT RUN line above)"; continue; fi
  [ $rc = 0 ] || { echo "act $a ended with exit $rc"; exit $rc; }
done
