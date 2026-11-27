#!/bin/bash
# Serve Inkling 2 Mini on 127.0.0.1:8080, the address of the original llama.cpp deployment.
set -euo pipefail

ROOT=$(dirname "$(readlink -f "$0")")
GGUF=/home/shared/models/Inkling-2-Mini-GGUF
MTP=/home/shared/models/Inkling-2-Mini/mtp.safetensors
HOST=127.0.0.1
PORT=8080

usage() {
  cat <<EOF
usage: serve.sh <engine> [--drafter [on|off]] [--ctx TOKENS]    start in the background
       serve.sh stop                                              stop your server

engines
  maya-q4   Maya, UD-Q4_K_XL
  maya-q8   Maya, UD-Q8_K_XL (converted to FP8 experts)
  llama     llama.cpp, UD-Q4_K_M (the original deployment's model and flags)

options
  --drafter [on|off]   speculative decoding with the drafter model (default: off)
  --ctx TOKENS         context shared by the 4 slots (default: 65536; llama: 16384)

Serves http://$HOST:$PORT/v1. It keeps running after you log out.
EOF
}

# stop your own server: ask it to finish, force it after a minute
stop() {
  local mine="-u $(id -u) -f ^$ROOT/(venv|engines)/"
  if ! pgrep $mine >/dev/null; then
    [ -z "$(ss -ltnH "sport = :$PORT")" ] && { echo "No server is running."; return 0; }
    echo "The server on port $PORT is not yours; only the person who started it can stop it." >&2
    return 1
  fi
  pkill -TERM -u "$(id -u)" -f "^$ROOT/(venv/bin/python|engines/llama.cpp/llama-server) " || true
  for _ in $(seq 60); do
    pgrep $mine >/dev/null || { echo "Stopped."; return 0; }
    sleep 1
  done
  pkill -KILL $mine || true
  echo "Stopped (forced)."
}

ENGINE= DRAFTER=off CTX=
while [ $# -gt 0 ]; do
  case $1 in
    maya-q4|maya-q8|llama) ENGINE=$1 ;;
    stop) stop; exit ;;
    --drafter) if [ "${2:-}" = on ] || [ "${2:-}" = off ]; then DRAFTER=$2; shift; else DRAFTER=on; fi ;;
    --drafter=on|--drafter=off) DRAFTER=${1#*=} ;;
    --ctx) CTX=${2:?--ctx needs a number}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -n "$ENGINE" ] || { usage >&2; exit 2; }
if [ -z "$CTX" ]; then    # llama.cpp runs out of GPU memory at 65536
  if [ "$ENGINE" = llama ]; then CTX=16384; else CTX=65536; fi
fi
[[ $CTX =~ ^[0-9]+$ ]] || { echo "--ctx needs a number, got: $CTX" >&2; exit 2; }

if [ -n "$(ss -ltnH "sport = :$PORT")" ]; then
  echo "Port $PORT is already in use: a server is running. Stop it first: serve.sh stop" >&2
  exit 1
fi
BUSY=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader)
if [ -n "$BUSY" ]; then
  echo "The GPU is in use, not starting:" >&2
  for p in $BUSY; do ps -o user=,pid=,args= -p "$p" | cut -c1-150 >&2 || true; done
  exit 1
fi

# the model name the server reports (requests may use any name, so older client configs keep working)
case $ENGINE in *q8) MODEL_ID=inkling-2-mini-q8 ;; *) MODEL_ID=inkling-2-mini-q4 ;; esac

LOG=$ROOT/logs/$ENGINE-$(id -un)-$(date +%Y%m%d-%H%M%S).log

# run a command detached from this terminal, then wait until it answers
launch() {
  setsid "$@" >>"$LOG" 2>&1 </dev/null &
  local server=$!
  trap 'echo; stop; exit 130' INT TERM
  echo -n "Starting $ENGINE (drafter $DRAFTER, context $CTX)"
  for _ in $(seq 450); do
    if curl -sf -m 2 "http://$HOST:$PORT/health" >/dev/null; then
      echo " ready."
      echo "Model $MODEL_ID at http://$HOST:$PORT/v1"
      echo "Stop: $ROOT/serve.sh stop    Log: $LOG"
      return 0
    fi
    kill -0 "$server" 2>/dev/null || { echo " failed. End of $LOG:" >&2; tail -n 20 "$LOG" >&2; exit 1; }
    echo -n .
    sleep 2
  done
  echo " still not ready after 15 minutes. See $LOG, or stop it: $ROOT/serve.sh stop" >&2
  exit 1
}

if [ "$ENGINE" = llama ]; then
  BIN=$ROOT/engines/llama.cpp
  export LD_LIBRARY_PATH=$BIN${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  ARGS=(-m "$GGUF/Inkling-2-Mini-UD-Q4_K_M.gguf" -a "$MODEL_ID" -ngl 99 -c "$CTX" --host $HOST --port $PORT --jinja)
  if [ "$DRAFTER" = on ]; then
    ARGS+=(-md "$GGUF/dspark-Inkling-2-Mini-Q8_0.gguf" --spec-type draft-dspark --spec-draft-n-max 2 -ngld 99)
  fi
  launch "$BIN/llama-server" "${ARGS[@]}"
  exit
fi

# Maya reads its settings from a JSON file; write one for this run in a private directory
DIR=$ROOT/engines/$ENGINE
RUN=$(mktemp -d "${TMPDIR:-/tmp}/serve-maya.XXXXXX")
python3 - "$RUN/config.json" "$ENGINE" "$DRAFTER" "$CTX" "$DIR" "$GGUF/Old_Support" "$MTP" "$MODEL_ID" "$LOG" <<'PY'
import json, sys
out, engine, drafter, ctx, d, models, mtp, model_id, log = sys.argv[1:]
weights = {"maya-q4": "Inkling-2-Mini-UD-Q4_K_XL.gguf", "maya-q8": "Inkling-2-Mini-UD-Q8_K_XL-maya-fp8.gguf"}[engine]
args = ["--model", f"{models}/{weights}", "--max-context", ctx, "--parallel", "4", "--chunk", "512"]
env = {"IK2_GATE_TILE": "64", "IK2_GATE_BF16": "1", "IK2_Q8_UNROLL": "1", "IK2_BATCH_PREFILL": "1"}
if engine == "maya-q4":
    env["IK2_KV"] = "fp8"
if drafter == "on":
    args += ["--draft", mtp]
    env["IK2_DRAFT_CTX"] = "8192"
json.dump({"exe": f"{d}/build/maya-ik2", "args": args, "env": env, "cwd": d, "tokenizer": f"{d}/ik2/tokenizer",
           "model_name": model_id, "fit_max_tokens": True, "log": log}, open(out, "w"), indent=1)
PY
cd "$DIR"
export MAYA_UPDATE_CHECK=0 MAYA_SAVINGS_PATH=off PYTHONDONTWRITEBYTECODE=1
launch "$ROOT/venv/bin/python" serve/server.py --engine maya --config "$RUN/config.json" --host $HOST --port $PORT
