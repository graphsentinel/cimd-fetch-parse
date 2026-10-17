# Evidence

Lab output of the reference runs, as produced (not edited). Each run directory holds `summary.md` (the fail-closed
summary), `measurements.tsv` (every recorded field), the step logs and `raw-evidence-*.tar.gz` (per attempt:
`requests.jsonl` from the recording proxy, `observed.jsonl`, the three Keycloak server logs, `metadata-requests.jsonl`,
`stdout.txt`, `manifest.json`). Request headers, request bodies and token responses were never written; the lab admin
password was generated inside each VM and is not in any file here.

| Run | Source | Keycloak | Plan | Result |
|---|---|---|---|---|
| [e2e-multipass/20261013T175141Z-ubuntu26.04](e2e-multipass/20261013T175141Z-ubuntu26.04/) | clean Ubuntu 26.04 VM, committed tree `a904d4e` | 26.7.0, 26.8.0 | RUNS=5 (100 cells), then reinstall + RUNS=1 (20), uninstall | 100/100 and 20/20 PASS, Problems: 0; 24 attempts ended `NOT RUN [vendor-fetch]` and passed on retry |
| [e2e-multipass/20261013T175201Z-ubuntu24.04](e2e-multipass/20261013T175201Z-ubuntu24.04/) | clean Ubuntu 24.04 VM, committed tree `a904d4e` | 26.7.0, 26.8.0 | RUNS=1 (20), then reinstall + RUNS=1 (20), uninstall | 20/20 and 20/20 PASS, Problems: 0 |
| [host-26.8.1](host-26.8.1/) | Ubuntu 26.04.1 host, commit `c46e9a9` | 26.8.1 | RUNS=3 (30), `PORT_BASE=18300` | 30/30 PASS, Problems: 0; same expected values as 26.7.0 / 26.8.0 |

Real agent clients (Codex CLI, goose, Hermes, opencode, Copilot CLI) against an MCP server behind the lab Keycloak:
[real-clients/](real-clients/) (23 counted attempts, 13 not counted with reasons).

`c46e9a9` → `a904d4e` changed only the lab's ownership checks (`scripts/lab.sh`, the premise line of check 03, `tls.sh`,
`platform.sh`), not what any check requests or how it decides.

A `NOT RUN [vendor-fetch]` attempt is Keycloak's first fetch of a vendor document timing out (a `java.net` exception
in that request's server log); it is kept on disk and never counted as a result.
