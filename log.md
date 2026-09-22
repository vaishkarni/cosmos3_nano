# log.md — how this repo came to be

Chronological record of the work on 2026-09-21/22 to get the DLI Cosmos 3 notebooks running
on Brev. Times are approximate; commit hashes refer to this repo.

## Starting point (2026-09-21)

- Only the DLI archive (`archive_name.zip`: four notebooks, `assets/`, `images/`) was
  available; no DLI lab access. The notebooks assume a container that was not shipped:
  Docker Compose service `cosmos3-reasoner` (NIM), `/opt/cosmos`, `/opt/cosmos3-framework`
  with a `.venv`, kernel `cosmos3`, Jupyter at `/lab` with root `/dli/task`, two GPUs
  (NIM on GPU 0, generation on GPU 1).
- Surveyed upstream: NIM image `nvcr.io/nim/nvidia/cosmos3-reasoner:1.7.0`;
  cosmos-framework installs with `uv sync --all-extras --group=cu130-train|cu128-train`
  (Python 3.13); `nvidia/Cosmos3-Nano` and `-Policy-DROID` open on HF, `Cosmos-Guardrail1`
  gated; cosmos-framework issue #221 (serving the reasoner via the framework fails) → use
  the NIM.

## 2026-09-22

### Instance choice
- Question: H100 or H200. Answer: 1x H100 (80 GB) suffices if the NIM is stopped before
  03/04; 1x H200 (141 GB) lets NIM and generation coexist. User chose **1x H200, 256 GB
  disk** (Brev machine `gpu-h200-sxm.1gpu-16vcpu-200gb`, Ubuntu 24.04, driver 580 /
  CUDA 13.0, Docker 29 with nvidia runtime).
- Correction along the way: an earlier "NIM needs ≥ 23.1 GiB" figure was wrong; the 1.7.0
  support matrix says > 56 GB BF16 / 48 GB L40S FP8 at default utilisation.

### First (interactive) bootstrap — `brev/` on the laptop, now superseded
- Wrote `bootstrap.sh`, `nim.sh`, `start-jupyter.sh`; uploaded with `brev copy`
  (note: `brev copy <dir>` copies the *contents* into the target, so the scripts landed
  in `~`).
- Bug: the zip has no top-level folder, so `unzip -d ~` scattered files; fixed by extracting
  into a fresh `archive_name/`.
- Bootstrap then completed: `/opt/cosmos`, `/opt/cosmos3-framework/.venv`
  (torch 2.10.0+cu130), `/opt/dli-jupyter`, kernel `cosmos3` with
  `CUDA_VISIBLE_DEVICES=0`, `/etc/hosts` alias, `~/.cosmos3-dli.env`.

### VS Code instead of Jupyter Lab
- User opened the box with `brev open <instance> code`. Guidance: pick kernels
  `/opt/dli-jupyter/bin/python` (01/02) and `cosmos3` (03/04); run `hf auth login` in the
  terminal; 04's `preview()` would not render in VS Code.
- A reconnect timed out: VS Code had picked `<instance>-host` (direct IP
  204.12.188.93:49369, unreachable from the user's network). The proxied alias
  `<instance>` works.

### NIM memory
- NIM came up healthy but held **128 GB**: its log showed `gpu_memory_utilization: 0.9`;
  `NIM_KVCACHE_PERCENT=0.2` had been passed and ignored. Grepped the container:
  `/opt/nim/inference.py` reads `NIM_GPU_MEMORY_UTILIZATION` (default 0.90) and
  `NIM_MAX_MODEL_LEN`; its own L40S profile uses 0.80 / 200000.
- `nim.sh` switched to `NIM_GPU_MEMORY_UTILIZATION=0.30`, `NIM_MAX_MODEL_LEN=200000`;
  after restart: **42–43 GB** used, `/v1/health/ready` ok.

### Hugging Face
- User logged in from the terminal (`hf auth whoami` → ok). Checked with
  `HfApi().auth_check`: access to `nvidia/Cosmos-Guardrail1` granted; Cosmos3-Nano repos
  open.
- Notebook 02 ran: `NIM ready after 0s. Serving model: nvidia/cosmos3-nano-reasoner`.

### This repo (github.com/vaishkarni/cosmos3_nano)
- Goal: a launchable whose setup script clones the repo and runs `brev-setup.sh` with
  launch parameters `NGC_API_KEY` and `HF_TOKEN`.
- `71b9c23` initial commit: `brev-setup.sh` (root) → `setup/user-setup.sh` (ubuntu),
  `setup/nim.sh`, `setup/start-jupyter.sh`, notebooks with kernel metadata
  `dli-python3` / `cosmos3`, only the referenced assets (6 MB instead of 136), README.
  Tested by copying the repo to the instance and running `sudo -E bash brev-setup.sh`:
  exit 0, `SETUP COMPLETE`, both kernels registered, torch sees CUDA.
- `e76491f` dropped the obsolete `huggingface_hub[cli]` extra. Pushed over SSH.
- Launchable form: 1x H200, 256 GiB, VM mode, Brev Jupyter off, no source files,
  launch parameters `NGC_API_KEY` (required) + `HF_TOKEN`, setup script:
  ```bash
  #!/bin/bash
  set -euo pipefail
  git clone -q https://github.com/vaishkarni/cosmos3_nano.git "$HOME/cosmos3_nano"
  sudo -E bash "$HOME/cosmos3_nano/brev-setup.sh"
  ```

### Notebook 04 fixes (from the Claude Code session inside VS Code on the instance)
- Its transcript (`~/.claude/projects/-home-ubuntu/…jsonl`) showed: forward dynamics
  produced a video but `preview()` rendered nothing; inverse-dynamics cell failed with
  `ModuleNotFoundError: cosmos_framework.data.vfm` (module moved in cosmos-framework
  1.2.2, release 2026-09-20); policy spec used `model_mode: policy`, which is not in
  `ModelMode` — the framework calls it `wam`. It also filtered the inference logs and ran
  the notebook end-to-end with nbconvert.
- `677e263` ported that version into `notebooks/04` (outputs stripped) and documented the
  changes in the README. 03 was checked against the same framework: modes, spec and asset
  paths all resolve; no changes needed.
- Laptop `archive_name/04` overwritten with the corrected notebook; `dli_original/`
  extracted from the zip as the read-only pristine reference.

### Output rerouting
- `87fe52a`: new `outputs/notebook1..4/`; env var `DLI_OUTPUTS` on both kernelspecs and in
  `~/.cosmos3-dli.env`; 02 writes `h264_cache/`, `robot_workspace_marked.png`, the
  grounding/trajectory overlays and `responses.jsonl`; 03 writes `payloads/` and run
  folders; 04 writes `inputs/`, run folders and `_previews/`. `COSMOS3_OUTPUT_ROOT` still
  overrides for 03/04.
- Verified on the instance by re-running `brev-setup.sh` and executing trimmed copies with
  nbconvert in the proper kernels — 02: cells 0–11 + 27 (`dli-python3`); 03: cells 0–9,
  13, 17 (`cosmos3`); 04: cells 0–7, 12, 19 (`cosmos3`). All clean; files landed only
  under `outputs/notebookN/`.
- Laptop `archive_name/02–04` synced to the repo notebooks.

## Current state of the instance `cosmos3-6f14bf`
- `~/cosmos3_nano` (this repo, copied; `/dli/task` → its `notebooks/`), `~/nim.sh` and
  `~/start-jupyter.sh` symlinked into it, `~/archive_name` (earlier copy with the user's
  executed 02, left untouched), earlier 04 GPU outputs under
  `/opt/cosmos3-framework/outputs/action/`.
- NIM running with the 0.30 cap; HF logged in; kernels `dli-python3` + `cosmos3` with
  `DLI_OUTPUTS` set.

## Open items
- The `HF_TOKEN` login path and the NIM cold start from `brev-setup.sh` have not been
  exercised on a fresh instance yet (both were done manually on this one). Check
  `~/brev-setup.log` on the first deploy of the launchable.
- Generation VRAM for Cosmos3-Nano at 720p / 189 frames alongside the NIM is still
  unmeasured; fallbacks are `NIM_GPU_MEMORY_UTILIZATION=0.2`, `~/nim.sh stop`, smaller
  `resolution` / `num_frames` / `num_steps`, `--no-guardrails`.
