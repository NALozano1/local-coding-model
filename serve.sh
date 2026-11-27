#!/bin/bash
# Serve Inkling 2 Mini on 127.0.0.1:8080 with llama.cpp or Maya.
set -euo pipefail

ROOT=$(dirname "$(readlink -f "$0")")
MODELS=${MODELS:-$ROOT/models}                             # the model files
LLAMA_BIN=${LLAMA_BIN:-$ROOT/engines/llama.cpp/build/bin}  # where llama-server was built
MTP=$MODELS/mtp.safetensors
HOST=127.0.0.1
PORT=8080

usage() {
  cat <<EOF
usage: serve.sh <engine> [--drafter [on|off]] [--ctx TOKENS]

engines
  maya-q4   Maya, UD-Q4_K_XL
  maya-q8   Maya, UD-Q8_K_XL (converted to FP8 experts)
  llama     llama.cpp, UD-Q4_K_M

options
  --drafter [on|off]   speculative decoding with the drafter model (default: off)
  --ctx TOKENS         context shared by the 4 slots (default: 16384)

Serves http://$HOST:$PORT/v1 in the foreground. Stop with Ctrl+C.
EOF
}

ENGINE= DRAFTER=off CTX=16384
while [ $# -gt 0 ]; do
  case $1 in
    maya-q4|maya-q8|llama) ENGINE=$1 ;;
    --drafter) if [ "${2:-}" = on ] || [ "${2:-}" = off ]; then DRAFTER=$2; shift; else DRAFTER=on; fi ;;
    --drafter=on|--drafter=off) DRAFTER=${1#*=} ;;
    --ctx) CTX=${2:?--ctx needs a number}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -n "$ENGINE" ] || { usage >&2; exit 2; }
[[ $CTX =~ ^[0-9]+$ ]] || { echo "--ctx needs a number, got: $CTX" >&2; exit 2; }

if [ -n "$(ss -ltnH "sport = :$PORT")" ]; then
  echo "Port $PORT is already in use: a server is running. Stop it first (README, 'Change the model')." >&2
  exit 1
fi
BUSY=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader)
if [ -n "$BUSY" ]; then
  echo "The GPU is in use, not starting:" >&2
  for p in $BUSY; do ps -o user=,pid=,args= -p "$p" | cut -c1-150 >&2 || true; done
  exit 1
fi

# the model name the server reports (requests may use any name)
case $ENGINE in *q8) MODEL_ID=inkling-2-mini-q8 ;; *) MODEL_ID=inkling-2-mini-q4 ;; esac

mkdir -p "$ROOT/logs"
LOG=$ROOT/logs/$ENGINE-$(id -un)-$(date +%Y%m%d-%H%M%S).log
echo "engine=$ENGINE drafter=$DRAFTER ctx=$CTX model=$MODEL_ID url=http://$HOST:$PORT/v1 log=$LOG"

if [ "$ENGINE" = llama ]; then
  BIN=$LLAMA_BIN
  export LD_LIBRARY_PATH=$BIN${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  ARGS=(-m "$MODELS/Inkling-2-Mini-UD-Q4_K_M.gguf" -a "$MODEL_ID" -ngl 99 -c "$CTX" --host $HOST --port $PORT --jinja)
  if [ "$DRAFTER" = on ]; then
    ARGS+=(-md "$MODELS/dspark-Inkling-2-Mini-Q8_0.gguf" --spec-type draft-dspark --spec-draft-n-max 2 -ngld 99)
  fi
  exec "$BIN/llama-server" "${ARGS[@]}" > >(tee "$LOG") 2>&1
fi

# Maya reads its settings from a JSON file; write one for this run in a private directory
DIR=$ROOT/engines/$ENGINE
RUN=$(mktemp -d "${TMPDIR:-/tmp}/serve-maya.XXXXXX")
python3 - "$RUN/config.json" "$ENGINE" "$DRAFTER" "$CTX" "$DIR" "$MODELS" "$MTP" "$MODEL_ID" "$LOG" <<'PY'
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
exec "$ROOT/venv/bin/python" serve/server.py --engine maya --config "$RUN/config.json" --host $HOST --port $PORT
