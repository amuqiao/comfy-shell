#!/usr/bin/env bash
# models.sh - optional model catalog helper for comfy-shell

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG_FILE="${CATALOG_FILE:-$ROOT_DIR/configs/models/catalog.yaml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
UV_BIN="${UV_BIN:-uv}"
HF_CLI="${HF_CLI:-hf}"

usage() {
  cat <<'EOF'
用法:
  ./scripts/models.sh <command> [bundle]
  ./scripts/models.sh -h|--help

作用域:
  可选的 ComfyUI 模型资产入口。读取 configs/models/catalog.yaml, 列出教程模型包,
  检查本地文件, 预览下载计划, 并在用户显式执行时调用 Hugging Face CLI 下载。

不负责:
  不参与 dev.sh bootstrap, 不自动下载模型, 不删除模型文件, 不安装 third-party custom_nodes,
  不修改 ComfyUI 已跟踪源码文件。

运行环境:
  Requires: Bash
  list/status/plan 需要 Python + PyYAML。优先使用仓库 .venv/bin/python。
  download 需要 hf CLI; 如果系统没有 hf, 会尝试使用 uv run hf。

命令:
  list                列出 catalog 中的 bundle
  status [bundle]     检查 bundle 模型文件是否存在且非空
  plan <bundle>       输出下载目标路径和 hf download 命令
  download <bundle>   显式下载 bundle 中的模型文件
  help                显示本帮助

配置与环境变量:
  COMFY_MODEL_ROOT    通过 .env 设置模型根目录; 默认 ./ComfyUI/models
  HF_ENDPOINT         可选, 例如 https://hf-mirror.com
  CATALOG_FILE        可选, 覆盖 catalog 路径
  PYTHON_BIN          可选, 覆盖 Python 路径
  HF_CLI              可选, 覆盖 hf CLI 路径

副作用与保护边界:
  list/status/plan 只读, 不访问网络。
  download 会创建模型子目录并写模型文件; 默认写入 ComfyUI/models 下的模型资产目录。
  download 必须由用户显式执行, 不修改 ComfyUI 已跟踪源码文件。
  所有相对模型路径按仓库根目录解析。

常用示例:
  ./scripts/models.sh list
  ./scripts/models.sh status
  ./scripts/models.sh status sdxl-basic
  ./scripts/models.sh plan sdxl-basic
  HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download sdxl-basic
  ./scripts/models.sh plan wan22-i2v-basic

Exit Codes:
  0  成功
  2  缺少 command、非法参数、catalog 缺失、Python/PyYAML/hf 缺失
  4  模型文件缺失、为空或下载失败
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

section() {
  printf '\n===== %s =====\n' "$1"
}

event() {
  printf '%-10s %-22s %s\n' "$1" "$2" "${3:-}"
}

env_value_from() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      line=$0
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)
      pattern="^[[:space:]]*" key "[[:space:]]*="
      if (line ~ pattern) {
        sub(/^[^=]*=/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
          line=substr(line, 2, length(line) - 2)
        }
        value=line
      }
    }
    END { if (value != "") print value }
  ' "$file"
}

model_root() {
  local configured
  configured="$(env_value_from COMFY_MODEL_ROOT "$ENV_FILE")"
  configured="${configured:-./ComfyUI/models}"
  case "$configured" in
    /*) printf '%s' "$configured" ;;
    *) printf '%s/%s' "$ROOT_DIR" "$configured" ;;
  esac
}

require_catalog() {
  [[ -f "$CATALOG_FILE" ]] || die "catalog not found: $CATALOG_FILE" 2
}

require_python_yaml() {
  [[ -x "$PYTHON_BIN" ]] || PYTHON_BIN="$(command -v python3 2>/dev/null || true)"
  [[ -n "$PYTHON_BIN" ]] || die "python not found; run ./scripts/dev.sh bootstrap first" 2
  "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1 || die "PyYAML not available in $PYTHON_BIN; run ./scripts/dev.sh bootstrap first" 2
import yaml
PY
}

catalog_python() {
  require_catalog
  require_python_yaml
  MODEL_ROOT="$(model_root)" "$PYTHON_BIN" - "$CATALOG_FILE" "$@" <<'PY'
import os
import sys
from pathlib import Path

import yaml

catalog_path = Path(sys.argv[1])
mode = sys.argv[2]
bundle_name = sys.argv[3] if len(sys.argv) > 3 else ""
model_root = Path(os.environ["MODEL_ROOT"])

with catalog_path.open("r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

bundles = data.get("bundles") or {}

def bundle_items():
    if bundle_name:
        if bundle_name not in bundles:
            print(f"ERROR: unknown bundle: {bundle_name}", file=sys.stderr)
            raise SystemExit(2)
        return [(bundle_name, bundles[bundle_name])]
    return sorted(bundles.items())

def model_path(model):
    return model_root / model["directory"] / model["filename"]

if mode == "list":
    for name, bundle in sorted(bundles.items()):
        print(f"{name}\t{bundle.get('title', '')}\t{bundle.get('tutorial', '')}")
elif mode == "status":
    missing = 0
    for name, bundle in bundle_items():
        print(f"## {name} - {bundle.get('title', '')}")
        for model in bundle.get("models") or []:
            path = model_path(model)
            if path.is_file() and path.stat().st_size > 0:
                size = path.stat().st_size
                print(f"OK\t{model['id']}\t{path}\t{size}")
            else:
                missing += 1
                print(f"MISSING\t{model['id']}\t{path}")
    raise SystemExit(4 if missing else 0)
elif mode == "plan":
    for name, bundle in bundle_items():
        print(f"## {name} - {bundle.get('title', '')}")
        if bundle.get("blueprint"):
            print(f"blueprint: {bundle['blueprint']}")
        if bundle.get("tutorial"):
            print(f"tutorial: {bundle['tutorial']}")
        for model in bundle.get("models") or []:
            if model.get("source", "huggingface") != "huggingface":
                print(f"UNSUPPORTED\t{model['id']}\tsource={model.get('source')}")
                continue
            path = model_path(model)
            print(f"TARGET\t{model['id']}\t{path}")
            print(f"HF\t{model['repo']}\t{model['path']}\t--local-dir {path.parent}")
else:
    print(f"ERROR: unknown mode: {mode}", file=sys.stderr)
    raise SystemExit(2)
PY
}

hf_command() {
  if command -v "$HF_CLI" >/dev/null 2>&1; then
    printf '%s' "$HF_CLI"
    return
  fi
  command -v "$UV_BIN" >/dev/null 2>&1 || die "hf CLI not found and uv not available" 2
  printf '%s run hf' "$UV_BIN"
}

download_bundle() {
  local bundle="$1"
  require_catalog
  require_python_yaml
  [[ -n "$bundle" ]] || die "download requires bundle" 2
  local hf
  hf="$(hf_command)"
  section "Download Plan"
  catalog_python plan "$bundle"
  section "Download"
  MODEL_ROOT="$(model_root)" "$PYTHON_BIN" - "$CATALOG_FILE" "$bundle" <<'PY' | while IFS=$'\t' read -r repo remote_path local_dir; do
import os
import sys
from pathlib import Path

import yaml

catalog_path = Path(sys.argv[1])
bundle_name = sys.argv[2]
model_root = Path(os.environ["MODEL_ROOT"])
data = yaml.safe_load(catalog_path.read_text(encoding="utf-8")) or {}
bundle = (data.get("bundles") or {}).get(bundle_name)
if bundle is None:
    print(f"ERROR: unknown bundle: {bundle_name}", file=sys.stderr)
    raise SystemExit(2)
for model in bundle.get("models") or []:
    if model.get("source", "huggingface") != "huggingface":
        print(f"ERROR: unsupported source for {model['id']}", file=sys.stderr)
        raise SystemExit(2)
    target_dir = model_root / model["directory"]
    print(f"{model['repo']}\t{model['path']}\t{target_dir}")
PY
    mkdir -p "$local_dir"
    event "DOWNLOAD" "$(basename "$remote_path")" "$local_dir"
    # shellcheck disable=SC2086
    $hf download "$repo" "$remote_path" --local-dir "$local_dir"
  done
  section "Status"
  catalog_python status "$bundle"
}

command="${1:-}"
case "$command" in
  -h|--help|help)
    usage
    ;;
  list)
    shift
    [[ "$#" -eq 0 ]] || die "list takes no arguments" 2
    section "Model Bundles"
    catalog_python list
    ;;
  status)
    shift
    [[ "$#" -le 1 ]] || die "status takes zero or one bundle" 2
    section "Model Status"
    catalog_python status "${1:-}"
    ;;
  plan)
    shift
    [[ "$#" -eq 1 ]] || die "plan requires one bundle" 2
    section "Model Plan"
    catalog_python plan "$1"
    ;;
  download)
    shift
    [[ "$#" -eq 1 ]] || die "download requires one bundle" 2
    download_bundle "$1"
    ;;
  "")
    usage >&2
    exit 2
    ;;
  *)
    usage >&2
    die "unknown command: $command" 2
    ;;
esac
