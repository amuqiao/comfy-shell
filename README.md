# comfy-shell

Thin shell repository for managing ComfyUI across macOS learning machines and
Linux CUDA servers. The shell owns the root `.env` config, scripts, model paths,
ComfyUI-Manager readiness, and process lifecycle. The upstream ComfyUI source
stays inside the `ComfyUI/` submodule.

## Layout

```text
comfy-shell/
  ComfyUI/           # submodule: git@github.com:Comfy-Org/ComfyUI.git, branch master
  .env.example       # default project config example
  configs/models/    # optional model catalog
  scripts/           # shell-managed local scripts
  tools/             # one-off scaffolding tools
```

## First-Stage Architecture

The first stage deliberately does not support Docker. The supported path is:

```text
uv + repository .venv
default root .env config
ComfyUI git submodule
script-managed ComfyUI-Manager Python package readiness
optional script-managed model catalog checks/downloads
```

Third-party `custom_nodes` are intentionally not script-managed in this stage.
Use the ComfyUI web UI / Manager UI manually after the local service is running.

Create `.env` once before running lifecycle commands:

```bash
cp .env.example .env
```

`.env.example` keeps one concrete server CUDA example plus commented macOS
overrides. Edit `.env` for the machine you are running on before lifecycle
commands. Treat `.env.example` as a copy/edit template, not as a runtime
`--profile` target.

Scripts read `.env` by default. Process environment variables override `.env`
values. Use `--profile FILE` only when you intentionally want a one-command
override from another config file. Do not commit `.env`.
Remote defaults such as `REMOTE_HOST`, `REMOTE_DIR`, and tunnel ports also live
in `.env`; keep the real host and path visible there instead of using aliases.

## Clone

```bash
git clone --recurse-submodules git@github.com:amuqiao/comfy-shell.git
cd comfy-shell
```

If the repository was cloned without submodules:

```bash
git submodule update --init --recursive
```

## Update ComfyUI

ComfyUI is tracked as a submodule on upstream `master`.

```bash
git submodule update --remote --merge ComfyUI
git add ComfyUI
git commit -m "Update ComfyUI submodule"
```

## Migrating An Existing Checkout

For an existing sibling checkout like `/Users/admin/Downloads/Code/ComfyUI`, move it into this repository instead of cloning another copy:

```bash
mv /Users/admin/Downloads/Code/ComfyUI /Users/admin/Downloads/Code/comfy-shell/ComfyUI
cd /Users/admin/Downloads/Code/comfy-shell
git submodule absorbgitdirs ComfyUI
git submodule init ComfyUI
git add .gitmodules ComfyUI
```

Keep shell scripts and configs in this repository, and keep upstream ComfyUI changes inside the `ComfyUI` submodule.

## Environment Check

Run the project-specific environment report before bootstrap or deployment:

```bash
./scripts/check_env.sh
./scripts/check_env.sh --no-network
```

The check is read-only. It verifies the shell repository, ComfyUI submodule,
config values, Python/uv, CUDA or MPS expectations, PyTorch import status,
model/output paths, port `8188`, and basic network reachability. It does not
install dependencies, download models, or start ComfyUI.

## Local macOS Run

Use the shell scripts to prepare and run ComfyUI with Manager enabled:

```bash
cp .env.example .env
# Edit .env for macOS: COMFY_PROFILE=macos-mps, COMFY_DEVICE=mps,
# TORCH_PRE=true, TORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cpu,
# COMFY_MODEL_ROOT=./ComfyUI/models, COMFY_OUTPUT_ROOT=./ComfyUI/output.
./scripts/check_env.sh --no-network
./scripts/local.sh bootstrap
./scripts/local.sh start
./scripts/local.sh status
```

Open:

```text
http://127.0.0.1:8188
```

Useful lifecycle commands:

```bash
./scripts/local.sh logs
./scripts/local.sh stop
./scripts/local.sh restart
./scripts/nodes.sh status
```

`local.sh bootstrap` creates the repository `.venv`, installs ComfyUI
requirements, and installs `ComfyUI/manager_requirements.txt` so `local.sh start`
can run `ComfyUI/main.py --enable-manager`. Startup arguments are assembled
from structured config keys such as `COMFY_HOST`, `COMFY_PORT`, and
`CUDA_VISIBLE_DEVICES`; config files are parsed as data and are not executed.
The shell script itself does not download models or install third-party
`custom_nodes`. Because `start` enables upstream ComfyUI-Manager, Manager may
run its own startup security checks or complete tasks that were previously
scheduled from the UI.

## Remote Server Run

Remote development reads visible `REMOTE_*` values from `.env` by default.
Before copying the commands below, make sure the local `.env` contains the real
remote target:

```dotenv
REMOTE_HOST=wangqiao@47.94.108.140
REMOTE_DIR=/data/wangqiao/comfy-shell
REMOTE_READY_URL=http://127.0.0.1:8188
REMOTE_TUNNEL_LOCAL_PORT=8188
REMOTE_TUNNEL_REMOTE_HOST=127.0.0.1
REMOTE_TUNNEL_REMOTE_PORT=8188
```

```bash
./scripts/remote.sh sync --yes
ssh wangqiao@47.94.108.140 'cd /data/wangqiao/comfy-shell && cp .env.example .env'
./scripts/remote.sh bootstrap --yes
./scripts/remote.sh start --yes
./scripts/remote.sh status
./scripts/remote.sh tunnel
./scripts/remote.sh gpu
```

Use `--host` or `--dir` only for one-off overrides. Write and lifecycle commands
still require `--yes` and print the resolved remote plan before execution.

## Business Tutorial

The tutorial path starts from the AI heroine short-video MVP and uses ComfyUI page templates or existing workflows before model-catalog automation. Start here:

```text
docs/tutorials/README.md
docs/tutorials/ai-heroine-content-pipeline.md
docs/tutorials/models.md
```

The current mainline is an original AI heroine short-video production pipeline:
identity assets, outfit changes, try-on keyframes, motion references, image-to-video,
audio/editing, and publishing assets.
