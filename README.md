# Cosmos 3 Nano on NVIDIA Brev

Runs the four NVIDIA DLI **Cosmos 3** course notebooks on a single-GPU
[NVIDIA Brev](https://brev.nvidia.com) instance, without DLI lab access. The DLI
container that the notebooks assume is rebuilt from public sources at first boot.

| Notebook | Kernel | What it does |
|---|---|---|
| `01_creating_huggingface_token` | Python 3 (DLI) | Hugging Face login (already done if you pass `HF_TOKEN`) |
| `02_world_reasoning` | Python 3 (DLI) | Asks the **Cosmos 3 Reasoner NIM** questions about videos (OpenAI API) |
| `03_world_generation` | Cosmos 3 (framework) | text2video, image2video, edge transfer with **Cosmos3-Nano** |
| `04_action_generation` | Cosmos 3 (framework) | forward / inverse dynamics and a policy with **Cosmos3-Nano** |

Everything is inference only; no fine-tuning happens here.

## 1. Create the launchable

Brev console → **Launchables → Create**:

| Section | Value |
|---|---|
| Hardware | 1× **H200** (141 GB), **Disk 256 GiB**. An 80 GB H100 also works, but then stop the NIM (`~/nim.sh stop`) before running 03/04. |
| Software | **VM Mode**. Leave Brev's Jupyter off (the notebooks run from VS Code). |
| Source | No code files attached |
| Launch parameters | `NGC_API_KEY` — required, text. `HF_TOKEN` — text (optional; skip it and run notebook 01 instead). |
| Setup script | see below |
| Network | nothing required. Optional Secure Link `lab` → port 8888 if you want Jupyter Lab instead of VS Code. |

Setup script (VM mode, runs as root with the launch parameters in its environment):

```bash
#!/bin/bash
set -euo pipefail
git clone -q https://github.com/vaishkarni/cosmos3_nano.git "$HOME/cosmos3_nano"
sudo -E bash "$HOME/cosmos3_nano/brev-setup.sh"
```

Where to get the keys:

- `NGC_API_KEY` — [ngc.nvidia.com](https://ngc.nvidia.com) → Setup → Generate API Key (free NVIDIA Developer Program account is enough). Used to pull `nvcr.io/nim/nvidia/cosmos3-reasoner:1.7.0` and its weights.
- `HF_TOKEN` — [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens), read scope. With that account, accept the licence of [`nvidia/Cosmos-Guardrail1`](https://huggingface.co/nvidia/Cosmos-Guardrail1) (the only gated model; `Cosmos3-Nano` and `Cosmos3-Nano-Policy-DROID` are open).

## 2. What the setup does (~20 min)

`brev-setup.sh` (root) then `setup/user-setup.sh` (as `ubuntu`), logged to `~/brev-setup.log`,
ending with `SETUP COMPLETE`:

1. apt packages (`ffmpeg`, `git-lfs`, `libx11-dev`, …) and [`uv`](https://docs.astral.sh/uv/)
2. `/dli/task` → `~/cosmos3_nano/notebooks` (path hard-coded in notebooks 02/04)
3. `/opt/cosmos` ← [NVIDIA/cosmos](https://github.com/NVIDIA/cosmos) cookbook (assets, prompts, specs)
4. `/opt/cosmos3-framework` ← [NVIDIA/cosmos-framework](https://github.com/NVIDIA/cosmos-framework), `uv sync --all-extras --group=cu130-train` (or `cu128-train`, chosen from the driver's CUDA version), plus `ipykernel imageio-ffmpeg matplotlib`
5. `/opt/dli-jupyter` — plain venv with `jupyterlab openai requests pillow huggingface_hub[cli]`
6. Jupyter kernels **`dli-python3`** (→ `/opt/dli-jupyter`) and **`cosmos3`** (→ `/opt/cosmos3-framework/.venv`). The notebooks' metadata names these kernels, so VS Code and Jupyter select the right environment automatically. `cosmos3` has `CUDA_VISIBLE_DEVICES=0` baked in (the DLI lab put generation on GPU 1).
7. `127.0.0.1 cosmos3-reasoner` in `/etc/hosts` (notebook 02's default `NIM_BASE_URL`)
8. `hf auth login` with `HF_TOKEN`
9. Starts the Reasoner NIM in the background with `NIM_GPU_MEMORY_UTILIZATION=0.30` so it takes ~43 GB of the H200 and leaves ~100 GB for 03/04 (see `setup/nim.sh` for why the documented `NIM_KVCACHE_PERCENT` does not work here). The key is also saved to `~/.ngc_api_key` (mode 600) so `~/nim.sh restart` works later.

## 3. Connect and run

```bash
brev ls                                  # wait for STATUS RUNNING
brev shell <instance>                    # then:  tail -f ~/brev-setup.log   (until SETUP COMPLETE)
~/nim.sh status                          # "ready" + ~43 GB used on the GPU
brev open <instance> code                # VS Code Remote-SSH into the box
```

If VS Code offers two hosts, pick `<instance>` (proxied), not `<instance>-host` (direct
IP; often blocked by firewalls).

In VS Code, open the folder `~/cosmos3_nano`, install the **Python** and **Jupyter**
extensions on the remote when prompted, and run `notebooks/01` → `02` → `03` → `04`.
Each notebook opens with its kernel preselected — `Python 3 (DLI)` for 01/02,
`Cosmos 3 (framework)` for 03/04. If VS Code asks, choose those names under
*Jupyter Kernel*.

- 01: skip if you passed `HF_TOKEN` (the `!hf auth login` cell is harmless to re-run).
- 02: the setup cell prints `Cosmos 3 Reasoner NIM: http://cosmos3-reasoner:8000` and the served model `nvidia/cosmos3-nano-reasoner`.
- 03: the first cell must print `CUDA_VISIBLE_DEVICES: 0`. The first run downloads Cosmos3-Nano (~minutes). Watch `nvidia-smi` in a terminal; the NIM stays up alongside.
- 04: patched against cosmos-framework 1.2.2 (see below); every generated clip renders inline.

### Changes to the DLI notebooks

01–03 are unmodified apart from kernel metadata. 04 needed fixes for the current framework
(release 2026-09-20) and for VS Code:

| Cell | DLI original | Here |
|---|---|---|
| `preview()` | `<video src="/lab/files/…">` — needs Jupyter Lab serving `/dli/task` at `/lab`; empty box in VS Code | transcodes a small copy and embeds it as a base64 data URI; also accepts URLs; cache keyed by run dir so every run's `vision.mp4` gets its own preview |
| inverse-dynamics visualisation | `from cosmos_framework.data.vfm.action.pose_utils import pose_rel_to_abs` | module moved: `cosmos_framework.data.generator.action.utils.pose_utils` |
| policy | `"model_mode": "policy"` | the framework calls this mode `"wam"` (world-action model); `policy` is not in `ModelMode` |
| the three `%%bash` inference cells | full log in the cell | piped through `grep -v` to hide the multi-KB config dump; the full log is still in `<output>/console.log` |

Prefer Jupyter Lab? `tmux new -s lab ~/start-jupyter.sh`, then
`brev port-forward <instance> -p 8888:8888` and open `http://localhost:8888/lab/?token=…`.

## 4. Day-to-day

```bash
~/nim.sh status|logs|restart|stop        # the Reasoner NIM container
brev stop <instance>                     # keeps the disk (all downloads); brev start to resume
sudo -E bash ~/cosmos3_nano/brev-setup.sh   # re-run setup (idempotent) after a failure
```

Env for shells and kernels lives in `~/.cosmos3-dli.env` (sourced from `~/.bashrc`):
`COSMOS_ROOT`, `COSMOS3_REPO`, `CUDA_VISIBLE_DEVICES=0`, `NIM_BASE_URL`, `HF_HOME`.

## 5. Troubleshooting

| Symptom | Fix |
|---|---|
| `nvidia-smi` shows the NIM using ~128 GB | It was started without the memory cap. `~/nim.sh restart`. |
| 03/04 OOM | `NIM_GPU_MEMORY_UTILIZATION=0.2 ~/nim.sh restart`, or `~/nim.sh stop` while generating; smaller `resolution` / `num_frames` / `num_steps` in `FIXED_SAMPLING`; `--no-guardrails` on the inference command. |
| 03 first cell prints `CUDA_VISIBLE_DEVICES: 1` | Kernel env not applied — pick the `Cosmos 3 (framework)` kernel explicitly, or `cat ~/.local/share/jupyter/kernels/cosmos3/kernel.json`. |
| 02: `NIM not ready` | `~/nim.sh logs`; first boot downloads ~10 GB of weights. |
| `403` downloading `Cosmos-Guardrail1` | Accept its licence on Hugging Face with the logged-in account (`hf auth whoami`). |
| Launchable setup failed | `cat ~/brev-setup.log`, fix, `sudo -E bash ~/cosmos3_nano/brev-setup.sh`. |

## Layout

```
brev-setup.sh            entry point (root); calls setup/user-setup.sh as ubuntu
setup/user-setup.sh      venvs, kernels, HF login, NIM
setup/nim.sh             start/stop/status/logs for the Reasoner NIM  (~/nim.sh)
setup/start-jupyter.sh   optional Jupyter Lab at /lab                 (~/start-jupyter.sh)
notebooks/               the four DLI notebooks (kernel metadata set), assets/toaster_6sec.mp4, images/
```

Upstream (NIM image tag, `uv` dependency groups, HF gating) moves quickly; the values
above were verified on 2026-09-22.
