#!/usr/bin/env bash
# every attempt on a freshly created realm (no client persisted by an earlier attempt)
cd "$(dirname "$0")"
for C in ${CLIENTS:-codex goose hermes opencode opencode19 opencodedev mcpremote}; do for S in stock ext; do for SC in "" openid; do
  ./realm.sh $S > /dev/null 2>&1 || { echo "realm $S failed"; continue; }
  CHALLENGE_SCOPE=$SC ./run.sh $C $S | tail -1
done; done; done
