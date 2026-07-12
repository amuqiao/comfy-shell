# comfy-shell

Thin shell repository for managing local ComfyUI setup around the upstream ComfyUI source tree.

## Layout

```text
comfy-shell/
  ComfyUI/   # submodule: git@github.com:Comfy-Org/ComfyUI.git, branch master
  configs/   # shell-managed local configs
  scripts/   # shell-managed local scripts
```

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
