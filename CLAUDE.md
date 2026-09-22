# CLAUDE.md — cosmos3_nano

## What this is

The four NVIDIA DLI **Cosmos 3** course notebooks, rebuilt to run on a single-GPU
**NVIDIA Brev** instance (target: 1x H200 141 GB, 256 GB disk, VM mode) without DLI lab
access. `brev-setup.sh` is the Brev launchable's setup script; it recreates the DLI
container's paths and services from public sources. All four notebooks are inference
only — nothing here fine-tunes a model.

This repo is cloned to `~/cosmos3_nano` on the instance. The user runs the notebooks from
**VS Code Remote-SSH** (`brev open <instance> code`), not Jupyter Lab. See `log.md` for the
history of how everything was arrived at.

## Layout

```
brev-setup.sh            root half of setup (apt, /dli/task, /etc/hosts, secrets, symlinks) -> calls user-setup.sh
setup/user-setup.sh      user half: uv venv for cosmos-framework, Jupyter venv, kernelspecs, HF login, NIM start
setup/nim.sh             ~/nim.sh: start|stop|restart|status|logs for the Reasoner NIM container
setup/start-jupyter.sh   optional Jupyter Lab at base URL /lab, root /dli/task
notebooks/               01-04 + assets/toaster_6sec.mp4 + images/ (only what the notebooks reference)
outputs/notebookN/       everything notebook N generates; skeleton tracked, contents git-ignored
```

## Environment the notebooks rely on

| Thing | Value | Set by |
|---|---|---|
| `/dli/task` | symlink -> `notebooks/` (hard-coded in 02 and 04) | brev-setup.sh |
| `COSMOS_ROOT` | `/opt/cosmos` — clone of github.com/NVIDIA/cosmos (cookbook assets/specs) | kernelspec env + `~/.cosmos3-dli.env` |
| `COSMOS3_REPO` | `/opt/cosmos3-framework` — clone of github.com/NVIDIA/cosmos-framework with `.venv` (`uv sync --all-extras --group=cu130-train`, Python 3.13) | same |
| `DLI_OUTPUTS` | `~/cosmos3_nano/outputs`; notebook N uses `$DLI_OUTPUTS/notebookN` | same |
| `CUDA_VISIBLE_DEVICES=0` | only on the `cosmos3` kernel — the notebooks `setdefault` it to `1` (DLI had 2 GPUs) | kernelspec env |
| `NIM_BASE_URL` | `http://cosmos3-reasoner:8000`; the hostname is an `/etc/hosts` alias for 127.0.0.1 | same |
| `HF_HOME` | `~/.cache/huggingface` (Brev symlinks `~/.cache` -> `/ephemeral/cache`, same disk) | same |
| kernel `dli-python3` | `/opt/dli-jupyter` venv (jupyterlab, openai, requests, pillow, huggingface_hub) — notebooks 01/02 | user-setup.sh |
| kernel `cosmos3` | `/opt/cosmos3-framework/.venv` + ipykernel, imageio-ffmpeg, matplotlib — notebooks 03/04 | user-setup.sh |
| NGC key | launch parameter `NGC_API_KEY`, persisted to `~/.ngc_api_key` (600) for `nim.sh` | brev-setup.sh |
| HF token | launch parameter `HF_TOKEN` -> `hf auth login` | user-setup.sh |

Notebook metadata `kernelspec.name` is `dli-python3` (01/02) or `cosmos3` (03/04) — keep
it that way so VS Code preselects the right environment.

## The Reasoner NIM (notebook 02)

- Image `nvcr.io/nim/nvidia/cosmos3-reasoner:1.7.0`, `NIM_MODEL_SIZE=nano`, served model
  `nvidia/cosmos3-nano-reasoner`, port 8000, cache `~/.cache/nim:/opt/nim/.cache`.
- **It must share the GPU with 03/04.** Its vLLM backend reserves
  `NIM_GPU_MEMORY_UTILIZATION` (default 0.90 = 128 GB of an H200) at start. `nim.sh` sets
  **0.30** + `NIM_MAX_MODEL_LEN=200000` (~43 GB used). The documented `NIM_KVCACHE_PERCENT`
  is **ignored by this image** — verified in its `/opt/nim/inference.py`. Weights are ~10 GiB
  (FP8 profile); the 1.7.0 support matrix's ">56 GB" figure is for the default utilisation.
- Health: `curl localhost:8000/v1/health/ready`. First start downloads ~10 GB.

## Changes vs the DLI originals

- 04: `from cosmos_framework.data.generator.action.utils.pose_utils import pose_rel_to_abs`
  (module moved in cosmos-framework 1.2.2, 2026-09-20); policy mode is `"wam"` (the
  framework's `ModelMode` has no `policy`); `preview()` embeds a downscaled clip as a base64
  data URI (VS Code has no Jupyter file server, so the DLI `/lab/files/...` URL showed an
  empty box) and accepts URLs; inference logs piped through `grep -v` (full log in
  `<output>/console.log`).
- 02–04: outputs routed to `outputs/notebookN/`; 02 also saves overlays and a
  `responses.jsonl` log.
- 01: untouched. `hf auth login` may also be done from a terminal; the `!hf` cell works in
  the `dli-python3` kernel because its kernelspec PATH includes the venv.

## Working here

- Test notebook edits without burning GPU time: trim a copy to the setup/spec cells and run
  `jupyter nbconvert --execute --ExecutePreprocessor.kernel_name=<kernel>` from
  `/opt/dli-jupyter/bin/jupyter` (see `log.md` for the exact cell ranges used).
- Setup scripts are idempotent; re-run with `sudo -E bash ~/cosmos3_nano/brev-setup.sh`,
  log in `~/brev-setup.log`.
- Never commit `~/.ngc_api_key`, tokens, or `outputs/` contents. Don't put secrets in the
  notebooks.
- VS Code Remote-SSH: use the proxied alias `<instance>`, not `<instance>-host` (direct IP,
  times out from some networks).
- Upstream moves daily (NIM tag, `uv` groups, framework module paths, HF gating —
  `nvidia/Cosmos-Guardrail1` is the only gated model). Re-check before changing versions.
- The laptop-side project (`../CLAUDE.md`, `../dli_original/`) keeps the pristine DLI copy;
  `notebooks/` here is the working version.
