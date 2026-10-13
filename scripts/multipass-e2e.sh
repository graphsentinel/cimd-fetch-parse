#!/usr/bin/env bash
# End-to-end check of the README quickstart in a fresh Ubuntu VM (multipass), from zero:
#   copy what a clone contains -> platform.sh install -> lab.sh all -> raw evidence
#   -> lab.sh reinstall + one more test round -> lab.sh uninstall -> platform.sh status.
#
#   scripts/multipass-e2e.sh                        Ubuntu 26.04, RUNS=5
#   UBUNTU=24.04 RUNS=1 scripts/multipass-e2e.sh
#
# Options (environment): UBUNTU (26.04), VM (cimd-e2e), CPUS (6), MEM (12G), DISK (30G), RUNS (5), VERSIONS
#   (versions.env default), REINSTALL_CHECK (1), KEEP (0: delete the VM afterwards when everything passed),
#   OUT_ROOT (evidence/e2e-multipass).
# Output: $OUT_ROOT/<UTC>-ubuntu<ver>/ (host.log, step logs, summary.md, measurements.tsv, raw-evidence-*.tar.gz).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
UBUNTU=${UBUNTU:-26.04}; VM=${VM:-cimd-e2e}; CPUS=${CPUS:-6}; MEM=${MEM:-12G}; DISK=${DISK:-30G}
RUNS=${RUNS:-5}; KEEP=${KEEP:-0}; REINSTALL_CHECK=${REINSTALL_CHECK:-1}; VERSIONS=${VERSIONS:-}
# the source state is read before this run writes anything (its own output directory may be inside the tree)
CLEAN=0; [ -z "$(cd "$ROOT" && git status --porcelain 2>/dev/null)" ] && CLEAN=1
OUT="${OUT_ROOT:-$ROOT/evidence/e2e-multipass}/$(date -u +%Y%m%dT%H%M%SZ)-ubuntu$UBUNTU"; mkdir -p "$OUT"
log(){ printf '\n==> %s\n' "$*" | tee -a "$OUT/host.log"; }

command -v multipass >/dev/null || { echo "multipass not installed (sudo snap install multipass)" >&2; exit 1; }
if multipass info "$VM" >/dev/null 2>&1; then echo "VM $VM exists; delete it first: multipass delete --purge $VM" >&2; exit 1; fi
log "launch $VM: Ubuntu $UBUNTU, $CPUS CPU, $MEM, $DISK"
multipass launch "$UBUNTU" --name "$VM" --cpus "$CPUS" --memory "$MEM" --disk "$DISK" --timeout 900
# the VM is kept when anything failed, so it can be inspected (delete it with: multipass delete --purge $VM)
cleanup(){ local s=$?; [ "$KEEP" = 1 ] || [ "$s" != 0 ] || [ "${rc:-1}" != 0 ] || { multipass delete --purge "$VM" 2>/dev/null || true; }; }
trap cleanup EXIT

# Source: the committed tree (git archive HEAD) when the working tree is clean — exactly what a clone gets.
# Streamed over stdin (the multipass snap cannot read the host's /tmp). evidence/ is not needed to run.
if [ "$CLEAN" = 1 ]; then
  SRC="committed tree $(cd "$ROOT" && git rev-parse HEAD)"
  pack(){ (cd "$ROOT" && git archive --format=tar.gz HEAD -- . ':(exclude)evidence'); }
else
  SRC="working tree with uncommitted changes (base $(cd "$ROOT" && git rev-parse --short HEAD 2>/dev/null || echo none)); NOT what a clone gets"
  pack(){ (cd "$ROOT" && git ls-files -co --exclude-standard | grep -v -E '^evidence/' | tar -czf - -T -); }
fi
log "copy source: $SRC"; echo "$SRC" > "$OUT/source.txt"
[ "$CLEAN" = 1 ] || (cd "$ROOT" && git status --short) >> "$OUT/source.txt"
pack | multipass exec "$VM" -- bash -c 'mkdir -p ~/lab && tar -xzf - -C ~/lab && find ~/lab -type f | wc -l'

run(){ # <log name> <command>: in a fresh login shell as the default user
  local name=$1; shift; log "$*"; local start=$SECONDS r=0
  multipass exec "$VM" -- sudo -iu ubuntu bash -lc "cd ~/lab && $*" 2>&1 | tee "$OUT/$name.log" || r=$?
  echo "$name: exit $r, $((SECONDS - start)) s" | tee -a "$OUT/host.log"; return $r; }
rc=0
step(){ [ $rc = 0 ] || return 0; run "$@" || rc=$?; }
V=${VERSIONS:+VERSIONS=\"$VERSIONS\" }
step 01-platform-install "scripts/platform.sh install"
step 02-lab-all "${V}RUNS=$RUNS scripts/lab.sh all"
capture(){ # raw evidence of every run (requests, responses, server logs), before anything is removed
  [ $rc = 0 ] || return 0
  multipass exec "$VM" -- bash -c 'cd ~/lab && tar -czf - lab/.runtime/runs lab/.runtime/plan-*.tsv lab/.runtime/summary.md results' > "$OUT/raw-evidence-$1.tar.gz" \
    && tar -tzf "$OUT/raw-evidence-$1.tar.gz" >/dev/null && echo "raw evidence: raw-evidence-$1.tar.gz" | tee -a "$OUT/host.log" \
    || { echo "raw evidence export failed ($1)" | tee -a "$OUT/host.log"; rc=1; }; }
capture main
multipass exec "$VM" -- bash -c 'cp ~/lab/lab/.runtime/summary.md ~/summary-main.md' || rc=1
if [ "$REINSTALL_CHECK" = 1 ]; then
  step 03-lab-reinstall "${V}scripts/lab.sh reinstall && ${V}scripts/lab.sh status"
  step 04-lab-test-after-reinstall "${V}RUNS=1 scripts/lab.sh test"
  capture after-reinstall
  step 05-lab-uninstall "${V}scripts/lab.sh uninstall"
  step 06-platform-after-uninstall "scripts/platform.sh status"
fi
log "fetch results"
multipass exec "$VM" -- bash -c 'cat ~/summary-main.md' > "$OUT/summary.md" && [ -s "$OUT/summary.md" ] \
  || { echo "fetch failed: summary.md" | tee -a "$OUT/host.log"; rc=1; }
multipass exec "$VM" -- bash -c 'cat ~/lab/results/measurements.tsv' > "$OUT/measurements.tsv" && [ "$(wc -l < "$OUT/measurements.tsv")" -gt 1 ] \
  || { echo "fetch failed: measurements.tsv" | tee -a "$OUT/host.log"; rc=1; }
multipass exec "$VM" -- bash -c 'lsb_release -ds; uname -r; nproc; free -h | head -2; podman --version 2>/dev/null; python3 --version' > "$OUT/environment.txt" 2>&1 || true
echo "result: exit $rc" | tee -a "$OUT/host.log"; echo "output: $OUT"
exit $rc
