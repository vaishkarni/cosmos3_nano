#!/usr/bin/env bash
# Entry point for the Brev launchable "Setup script" (VM mode). Brev runs it as root
# during first boot, with the launch parameters exported as environment variables:
#
#   NGC_API_KEY  (required)  free NVIDIA Developer Program key -> pulls + runs the Reasoner NIM
#   HF_TOKEN     (optional)  Hugging Face token -> `hf auth login`, so notebook 01 is already done
#
# Launchable setup script:
#   #!/bin/bash
#   set -euo pipefail
#   git clone -q https://github.com/vaishkarni/cosmos3_nano.git "$HOME/cosmos3_nano"
#   sudo -E bash "$HOME/cosmos3_nano/brev-setup.sh"
#
# Idempotent: re-run with `sudo -E bash ~/cosmos3_nano/brev-setup.sh` after a failure.
# Everything is logged to ~/brev-setup.log; the last line is "SETUP COMPLETE".
set -euo pipefail

TARGET_USER="${TARGET_USER:-${SUDO_USER:-ubuntu}}"
[[ "$TARGET_USER" == root ]] && TARGET_USER=ubuntu
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$TARGET_HOME/brev-setup.log"

if [[ $EUID -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi
touch "$LOG" && chown "$TARGET_USER:$TARGET_USER" "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "=== brev-setup.sh $(date -Is) user=$TARGET_USER repo=$REPO_DIR ==="

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

# ------------------------------------------------------------ root: packages
log "System packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  curl ffmpeg git git-lfs libx11-dev tree wget unzip tmux python3-venv python3-pip

# ------------------------------------------------- root: paths the DLI notebooks expect
log "Paths"
mkdir -p /dli && ln -sfn "$REPO_DIR/notebooks" /dli/task            # /dli/task hard-coded in 02/04
for d in /opt/cosmos /opt/cosmos3-framework /opt/dli-jupyter; do
  mkdir -p "$d" && chown "$TARGET_USER:$TARGET_USER" "$d"
done
grep -qE '\bcosmos3-reasoner\b' /etc/hosts || echo "127.0.0.1 cosmos3-reasoner" >> /etc/hosts   # 02's NIM_BASE_URL
# Brev images symlink ~/.cache -> /ephemeral/cache; make sure the target exists and is the user's
if [[ -L "$TARGET_HOME/.cache" && ! -e "$TARGET_HOME/.cache" ]]; then
  mkdir -p "$(readlink "$TARGET_HOME/.cache")" && chown "$TARGET_USER:$TARGET_USER" "$(readlink "$TARGET_HOME/.cache")"
fi
chown -R "$TARGET_USER:$TARGET_USER" "$REPO_DIR"

# ------------------------------------------------------- root: secrets + shell env
if [[ -n "${NGC_API_KEY:-}" ]]; then
  install -m 600 -o "$TARGET_USER" -g "$TARGET_USER" /dev/stdin "$TARGET_HOME/.ngc_api_key" <<<"$NGC_API_KEY"
fi
ln -sfn "$REPO_DIR/setup/nim.sh" "$TARGET_HOME/nim.sh"
ln -sfn "$REPO_DIR/setup/start-jupyter.sh" "$TARGET_HOME/start-jupyter.sh"
grep -q 'cosmos3-dli.env' "$TARGET_HOME/.bashrc" || echo 'source ~/.cosmos3-dli.env 2>/dev/null' >> "$TARGET_HOME/.bashrc"

# ---------------------------------------------- user: venvs, kernels, HF login, NIM
log "User-level setup as $TARGET_USER"
sudo -u "$TARGET_USER" -H \
  env NGC_API_KEY="${NGC_API_KEY:-}" HF_TOKEN="${HF_TOKEN:-}" UV_GROUP="${UV_GROUP:-auto}" REPO_DIR="$REPO_DIR" \
  bash "$REPO_DIR/setup/user-setup.sh"

log "SETUP COMPLETE $(date -Is)"
