# The demo, live

Four acts that run against the lab while you watch. Every line marked accepted or refused comes from a real request
answered just then; the reason next to it is read from that request's Keycloak log. Nothing is replayed.

| Act | What it shows | Needs |
|---|---|---|
| 1 | Stock Keycloak 26.8.0 and the eight published CIMD documents: 5 refused at parse time, the caller is told "Client Metadata fetch failed" | the lab, internet (the documents are fetched from their publishers) |
| 2 | A CIMD provider never sees a document whose parse failed (`createClientMetadata` 0 calls) | same |
| 3 | The `lenient-cimd` executor: 8 of 8 accepted with anonymous registration locked (403), and five negative controls each still refused for its own reason | same |
| 4 | A real agent, goose 1.55.0: no token from stock Keycloak, then a token and an MCP tool call with the executor | goose and a model it can use (below) |

## Run it

```sh
scripts/platform.sh install                  # podman (or docker), jq, curl, openssl, Python 3; once per machine
VERSIONS=26.8.0 scripts/lab.sh build install # Keycloak 26.8.0: stock, ext (this repository's jar), noflag
demo/run.sh                                  # all acts, about 6 minutes; steps advance on their own
demo/run.sh 1 3                              # only some acts
```

For act 4:

```sh
demo/install-goose.sh                        # goose 1.55.0 from its GitHub release, sha256 checked
ollama pull qwen3.6:35b                      # the default model; or set GOOSE_MODEL to one you have
GOOSE_MODEL=<model> demo/run.sh 4            # OLLAMA_HOST (http://localhost:11434); other providers: GOOSE_PROVIDER
```

Act 4 is skipped, with the reason, when goose or the model is missing. Its records (Keycloak events and log, MCP
server log, browser record) go to `lab/.runtime/real-clients/runs/`; the verdict lines are read from them, not from
goose's output. More clients: [real-clients/](../real-clients/).

## In a talk

```sh
VERSIONS=26.8.0 scripts/lab.sh status       # all four lines "ready"
demo/warm.sh                                 # a few minutes before: first fetch of every document (about 1.5 min)
WARM=0 demo/run.sh --present                 # a key advances each step; the screen is cleared between acts
```

- The documents are fetched live from their publishers. A refusal whose server log shows a network error is printed
  as "fetch did not complete (network): not a result", never as a parse refusal; run the act again.
- The metadata server's name is `<this host's IPv4 with dashes>.nip.io` (act 3). On another network the address
  changes: run `VERSIONS=26.8.0 scripts/lab.sh reinstall` there, or set `MD_HOST` when installing.
- Act 4 needs the model to answer in time (`GOOSE_TIMEOUT`, 90 s). Keep a recording of the demo as a fallback.
- `PAUSE`: seconds between steps when not presenting (1.2).

Realms the demo creates (`demo-*`, `agent-trial`, `agent-warm`) are replaced on every run and removed with the lab
(`scripts/lab.sh uninstall`).
