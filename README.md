# comfy-shell

Thin shell repository for managing ComfyUI across macOS learning machines and
Linux CUDA servers. The shell owns environment profiles, scripts, model paths,
ComfyUI-Manager readiness, and process lifecycle. The upstream ComfyUI source
stays inside the `ComfyUI/` submodule.

## Layout

```text
comfy-shell/
  ComfyUI/           # submodule: git@github.com:Comfy-Org/ComfyUI.git, branch master
  configs/profiles/  # macOS MPS / Linux CUDA profile templates
  scripts/           # shell-managed local scripts
  tools/             # one-off scaffolding tools
```

## First-Stage Architecture

The first stage deliberately does not support Docker. The supported path is:

```text
uv + repository .venv
explicit --profile file
ComfyUI git submodule
script-managed ComfyUI-Manager Python package readiness
optional script-managed model catalog checks/downloads
```

Third-party `custom_nodes` are intentionally not script-managed in this stage.
Use the ComfyUI web UI / Manager UI manually after the local service is running.

Recommended profiles:

```text
configs/profiles/macos-mps.env.example
configs/profiles/server-cuda-a10.env.example
```

Pass a profile explicitly to scripts that need runtime settings:

```bash
./scripts/check_env.sh --profile configs/profiles/macos-mps.env.example
```

For a server:

```bash
./scripts/check_env.sh --profile configs/profiles/server-cuda-a10.env.example
```

`.env` is optional local shorthand created by `./scripts/env.sh use <profile>`.
Scripts do not read it implicitly; pass `--profile .env` when you want to use it.
Do not commit `.env`.

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
./scripts/check_env.sh --profile configs/profiles/server-cuda-a10.env.example
./scripts/check_env.sh --no-network
```

The check is read-only. It verifies the shell repository, ComfyUI submodule,
profile values, Python/uv, CUDA or MPS expectations, PyTorch import status,
model/output paths, port `8188`, and basic network reachability. It does not
install dependencies, download models, or start ComfyUI.

## Local macOS Run

Use the shell scripts to prepare and run ComfyUI with Manager enabled:

```bash
./scripts/env.sh use macos-mps
./scripts/check_env.sh --profile .env --no-network
./scripts/local.sh bootstrap --profile .env
./scripts/local.sh start --profile .env
./scripts/local.sh status --profile .env
```

Open:

```text
http://127.0.0.1:8188
```

Useful lifecycle commands:

```bash
./scripts/local.sh logs
./scripts/local.sh stop --profile .env
./scripts/local.sh restart --profile .env
./scripts/nodes.sh status
```

`local.sh bootstrap` creates the repository `.venv`, installs ComfyUI
requirements, and installs `ComfyUI/manager_requirements.txt` so `local.sh start`
can run `ComfyUI/main.py --enable-manager`. Startup arguments are assembled
from structured profile keys such as `COMFY_HOST`, `COMFY_PORT`, and
`CUDA_VISIBLE_DEVICES`; profile files are parsed as data, only when passed with
`--profile`, and are not executed.
The shell script itself does not download models or install third-party
`custom_nodes`. Because `start` enables upstream ComfyUI-Manager, Manager may
run its own startup security checks or complete tasks that were previously
scheduled from the UI.

## Remote Server Run

Remote development uses explicit, copyable connection parameters:

```bash
./scripts/remote.sh sync --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --yes
./scripts/remote.sh bootstrap --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --profile configs/profiles/server-cuda-a10.env.example --yes
./scripts/remote.sh start --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --profile configs/profiles/server-cuda-a10.env.example --yes
./scripts/remote.sh status --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --profile configs/profiles/server-cuda-a10.env.example
./scripts/remote.sh tunnel --host wangqiao@47.94.108.140 --local-port 8188 --remote-port 8188
./scripts/remote.sh gpu --host wangqiao@47.94.108.140
```

`remote.sh` does not read `configs/remotes` and does not support hidden targets.
Commands print the resolved remote plan before write/lifecycle actions.

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
