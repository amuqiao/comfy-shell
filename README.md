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
```

## First-Stage Architecture

The first stage deliberately does not support Docker. The supported path is:

```text
uv + repository .venv
profile env file
ComfyUI git submodule
script-managed ComfyUI-Manager Python package readiness
future script-managed model downloads and checks
```

Third-party `custom_nodes` are intentionally not script-managed in this stage.
Use the ComfyUI web UI / Manager UI manually after the local service is running.

Recommended profiles:

```text
configs/profiles/macos-mps.env.example
configs/profiles/server-cuda-a10.env.example
```

Use a profile by copying it to `.env` and editing local paths:

```bash
cp configs/profiles/macos-mps.env.example .env
./scripts/check_env.sh
```

For a server:

```bash
cp configs/profiles/server-cuda-a10.env.example .env
./scripts/check_env.sh
```

The `.env` file is the active local profile and should not be committed.

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
./scripts/check_env.sh --no-network
./scripts/dev.sh bootstrap
./scripts/dev.sh start
./scripts/dev.sh status
```

Open:

```text
http://127.0.0.1:8188
```

Useful lifecycle commands:

```bash
./scripts/dev.sh logs
./scripts/dev.sh stop
./scripts/dev.sh restart
./scripts/nodes.sh status
```

`dev.sh bootstrap` creates the repository `.venv`, installs ComfyUI
requirements, and installs `ComfyUI/manager_requirements.txt` so `dev.sh start`
can run `ComfyUI/main.py --enable-manager`. Startup arguments are assembled
from structured profile keys such as `COMFY_HOST`, `COMFY_PORT`, and
`CUDA_VISIBLE_DEVICES`; profile files are parsed as data and are not executed.
The shell script itself does not download models or install third-party
`custom_nodes`. Because `start` enables upstream ComfyUI-Manager, Manager may
run its own startup security checks or complete tasks that were previously
scheduled from the UI.

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
