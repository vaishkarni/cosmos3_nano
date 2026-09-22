#!/usr/bin/env bash
# Optional: Jupyter Lab the way the DLI container served it (base URL /lab, root /dli/task).
# Not needed when running the notebooks from VS Code (brev open <instance> code).
#   tmux new -s lab ~/start-jupyter.sh      then  brev port-forward <instance> -p 8888:8888
set -euo pipefail
source "$HOME/.cosmos3-dli.env"

PORT="${JUPYTER_PORT:-8888}"
cd /dli/task
exec "$JUPYTER_VENV/bin/jupyter" lab \
  --ip=0.0.0.0 --port="$PORT" --no-browser \
  --ServerApp.base_url=/lab \
  --ServerApp.root_dir=/dli/task \
  --ServerApp.allow_remote_access=True \
  --ServerApp.allow_origin='*' \
  "$@"
