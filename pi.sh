#!/bin/bash
# Run the Pi coding agent on the server itself, against the model server on the same machine.
ROOT=$(dirname "$(readlink -f "$0")")
export PI_CODING_AGENT_DIR=$HOME/.pi-local-coding-model    # separate from any Pi setup of your own
mkdir -p "$PI_CODING_AGENT_DIR"
cp -n "$ROOT"/pi/*.json "$PI_CODING_AGENT_DIR"/            # first run only; your edits are kept
curl -sf -m 5 http://127.0.0.1:8080/health >/dev/null ||
  { echo "No model server is running. Start one with: $ROOT/serve.sh maya-q4" >&2; exit 1; }
export PATH=$ROOT/node/bin:$PATH
exec pi "$@"
