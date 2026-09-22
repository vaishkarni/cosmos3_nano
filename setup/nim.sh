#!/usr/bin/env bash
# Manage the Cosmos 3 Reasoner NIM container that notebook 02 talks to.
#   ~/nim.sh start|stop|restart|status|logs        (NIM_WAIT=0 start: don't block until ready)
#
# Single-GPU sharing: this NIM's vLLM backend reserves NIM_GPU_MEMORY_UTILIZATION
# (default 0.90) of *total* GPU memory - 128 GB of an H200 - which would leave
# nothing for the generation notebooks. (The generic NIM_KVCACHE_PERCENT variable
# from the NIM docs is NOT read by this image; /opt/nim/inference.py only honours
# NIM_GPU_MEMORY_UTILIZATION and NIM_MAX_MODEL_LEN.) Its own built-in profile for
# a 48 GB L40S is 0.80 x 48 = 38 GB with NIM_MAX_MODEL_LEN=200000; 0.30 x 143 GB
# = 43 GB gives it more than that and leaves ~100 GB for 03/04.
set -euo pipefail
source "$HOME/.cosmos3-dli.env" 2>/dev/null || true

IMG="${NIM_IMAGE:-nvcr.io/nim/nvidia/cosmos3-reasoner:1.7.0}"
NAME=cosmos3-reasoner
NIM_MODEL_SIZE="${NIM_MODEL_SIZE:-nano}"
NIM_GPU_MEMORY_UTILIZATION="${NIM_GPU_MEMORY_UTILIZATION:-0.30}"
NIM_MAX_MODEL_LEN="${NIM_MAX_MODEL_LEN:-200000}"
LOCAL_NIM_CACHE="${LOCAL_NIM_CACHE:-$HOME/.cache/nim}"
BASE_URL="${NIM_BASE_URL:-http://localhost:8000}"
NIM_WAIT="${NIM_WAIT:-1}"

start() {
  if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then echo "$NAME already running"; [[ "$NIM_WAIT" == 1 ]] && wait_ready; return; fi
  [[ -n "${NGC_API_KEY:-}" ]] || { [[ -f "$HOME/.ngc_api_key" ]] && NGC_API_KEY=$(<"$HOME/.ngc_api_key"); }
  [[ -n "${NGC_API_KEY:-}" ]] || { echo "export NGC_API_KEY=nvapi-... first (or put it in ~/.ngc_api_key)"; exit 1; }
  mkdir -p "$LOCAL_NIM_CACHE"
  echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name="$NAME" --restart=unless-stopped \
    --runtime=nvidia --gpus all --shm-size=32GB \
    -e NGC_API_KEY="$NGC_API_KEY" \
    -e NIM_MODEL_SIZE="$NIM_MODEL_SIZE" \
    -e NIM_GPU_MEMORY_UTILIZATION="$NIM_GPU_MEMORY_UTILIZATION" \
    -e NIM_MAX_MODEL_LEN="$NIM_MAX_MODEL_LEN" \
    -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
    -u "$(id -u)" \
    -p 8000:8000 \
    "$IMG"
  [[ "$NIM_WAIT" == 1 ]] && wait_ready || echo "started $NAME in the background; ~/nim.sh status to check"
}

wait_ready() {
  echo -n "Waiting for $BASE_URL/v1/health/ready (first start downloads the model; can take 10+ min) "
  for _ in $(seq 1 240); do
    if curl -fsS "$BASE_URL/v1/health/ready" >/dev/null 2>&1; then
      echo; curl -s "$BASE_URL/v1/models" | python3 -m json.tool 2>/dev/null | grep '"id"' || true
      nvidia-smi --query-gpu=memory.used,memory.total --format=csv
      return
    fi
    docker ps --format '{{.Names}}' | grep -qx "$NAME" || { echo; echo "container exited:"; docker logs --tail 50 "$NAME"; exit 1; }
    echo -n .; sleep 10
  done
  echo; echo "timed out - check ~/nim.sh logs"; exit 1
}

case "${1:-status}" in
  start)   start ;;
  stop)    docker stop "$NAME" && docker rm "$NAME" ;;
  restart) docker stop "$NAME" >/dev/null 2>&1 && docker rm "$NAME" >/dev/null 2>&1 || true; start ;;
  logs)    docker logs -f --tail 200 "$NAME" ;;
  status)  docker ps --filter "name=$NAME"; curl -s "$BASE_URL/v1/health/ready" && echo " ready" || echo "not ready"
           nvidia-smi --query-gpu=memory.used,memory.total --format=csv ;;
  *) echo "usage: $0 start|stop|restart|status|logs"; exit 2 ;;
esac
