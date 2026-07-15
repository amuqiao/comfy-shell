#!/usr/bin/env bash
# models.sh - optional model catalog helper for comfy-shell

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG_FILE="${CATALOG_FILE:-$ROOT_DIR/configs/models/catalog.yaml}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
UV_BIN="${UV_BIN:-uv}"
HF_CLI="${HF_CLI:-hf}"

usage() {
  cat <<'EOF'
用法:
  ./scripts/models.sh list
  ./scripts/models.sh status [bundle] [--profile FILE]
  ./scripts/models.sh plan <bundle> [--profile FILE]
  ./scripts/models.sh download <bundle> [--profile FILE]
  ./scripts/models.sh -h|--help

作用域:
  可选的 ComfyUI 模型资产入口。读取 configs/models/catalog.yaml, 列出教程模型包,
  检查本地文件, 预览下载计划, 并在用户显式执行时调用 Hugging Face CLI 下载。

不负责:
  不参与 local.sh bootstrap, 不自动下载模型, 不删除模型文件, 不安装 third-party custom_nodes,
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
  --profile FILE      status/plan/download 可显式指定 profile env 文件。
  COMFY_MODEL_ROOT    从显式 profile 读取; 未传 --profile 时固定默认 ./ComfyUI/models。
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
  ./scripts/models.sh status heroine-i2v-core --profile .env
  ./scripts/models.sh plan heroine-i2v-core --profile configs/profiles/macos-mps.env.example
  HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core --profile .env
  ./scripts/models.sh plan heroine-t2v-explore

Exit Codes:
  0  成功
  1  status 检查发现模型文件缺失或为空
  2  缺少 command、非法参数、catalog 缺失、Python/PyYAML/hf 缺失
  4  下载运行失败
EOF
}

command_usage() {
  local name="$1"
  case "$name" in
    list)
      cat <<'EOF'
用法:
  ./scripts/models.sh list
  ./scripts/models.sh list -h|--help

作用域:
  列出 catalog 中的 bundle。list 不需要 profile, 也不读取 .env。
EOF
      ;;
    status)
      cat <<'EOF'
用法:
  ./scripts/models.sh status [bundle] [--profile FILE]
  ./scripts/models.sh status -h|--help

作用域:
  检查 bundle 模型文件是否存在且非空。

配置:
  --profile FILE      可选; 只从显式 profile 读取 COMFY_MODEL_ROOT。
  默认模型根目录     未传 --profile 时使用 ./ComfyUI/models, 不隐式读取 .env。

常用示例:
  ./scripts/models.sh status
  ./scripts/models.sh status heroine-i2v-core --profile .env
  ./scripts/models.sh status --profile configs/profiles/macos-mps.env.example
EOF
      ;;
    plan)
      cat <<'EOF'
用法:
  ./scripts/models.sh plan <bundle> [--profile FILE]
  ./scripts/models.sh plan -h|--help

作用域:
  输出下载目标路径和 hf download 命令, 不访问网络。

配置:
  --profile FILE      可选; 只从显式 profile 读取 COMFY_MODEL_ROOT。
  默认模型根目录     未传 --profile 时使用 ./ComfyUI/models, 不隐式读取 .env。

常用示例:
  ./scripts/models.sh plan heroine-i2v-core
  ./scripts/models.sh plan heroine-i2v-core --profile .env
  ./scripts/models.sh plan heroine-i2v-core --profile configs/profiles/macos-mps.env.example
EOF
      ;;
    download)
      cat <<'EOF'
用法:
  ./scripts/models.sh download <bundle> [--profile FILE]
  ./scripts/models.sh download -h|--help

作用域:
  显式下载 bundle 中的模型文件。

配置:
  --profile FILE      可选; 只从显式 profile 读取 COMFY_MODEL_ROOT。
  默认模型根目录     未传 --profile 时使用 ./ComfyUI/models, 不隐式读取 .env。
  HF_ENDPOINT         可选环境变量, 例如 https://hf-mirror.com。

常用示例:
  HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core
  HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core --profile .env
  ./scripts/models.sh download heroine-i2v-core --profile configs/profiles/macos-mps.env.example
EOF
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
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

resolve_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$ROOT_DIR" "$1" ;;
  esac
}

MODEL_ARGS=()
PROFILE_FILE=""

parse_optional_profile_args() {
  local command_name="$1"
  shift
  MODEL_ARGS=()
  PROFILE_FILE=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ "$#" -ge 2 ]] || die "--profile requires a file" 2
        PROFILE_FILE="$2"
        shift 2
        ;;
      --profile=*)
        PROFILE_FILE="${1#--profile=}"
        shift
        ;;
      -*)
        die "$command_name unknown option: $1" 2
        ;;
      *)
        MODEL_ARGS+=("$1")
        shift
        ;;
    esac
  done
  if [[ -n "$PROFILE_FILE" ]]; then
    PROFILE_FILE="$(resolve_path "$PROFILE_FILE")"
    [[ -f "$PROFILE_FILE" ]] || die "profile not found: $PROFILE_FILE" 2
  fi
}

model_root() {
  local configured="./ComfyUI/models"
  if [[ -n "${PROFILE_FILE:-}" ]]; then
    configured="$(env_value_from COMFY_MODEL_ROOT "$PROFILE_FILE")"
    configured="${configured:-./ComfyUI/models}"
  fi
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
  [[ -n "$PYTHON_BIN" ]] || die "python not found; run ./scripts/local.sh bootstrap --profile FILE first" 2
  "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1 || die "PyYAML not available in $PYTHON_BIN; run ./scripts/local.sh bootstrap --profile FILE first" 2
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
    raise SystemExit(1 if missing else 0)
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

HF_CMD=()

resolve_hf_command() {
  if command -v "$HF_CLI" >/dev/null 2>&1; then
    HF_CMD=("$HF_CLI")
    return
  fi
  command -v "$UV_BIN" >/dev/null 2>&1 || die "hf CLI not found and uv not available" 2
  HF_CMD=("$UV_BIN" run hf)
}

download_bundle() {
  local bundle="$1"
  require_catalog
  require_python_yaml
  [[ -n "$bundle" ]] || die "download requires bundle" 2
  resolve_hf_command
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
    "${HF_CMD[@]}" download "$repo" "$remote_path" --local-dir "$local_dir"
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
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage list; exit 0; fi
    [[ "$#" -eq 0 ]] || die "list takes no arguments" 2
    section "Model Bundles"
    catalog_python list
    ;;
  status)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage status; exit 0; fi
    parse_optional_profile_args status "$@"
    [[ "${#MODEL_ARGS[@]}" -le 1 ]] || die "status takes zero or one bundle" 2
    section "Model Status"
    catalog_python status "${MODEL_ARGS[0]:-}"
    ;;
  plan)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage plan; exit 0; fi
    parse_optional_profile_args plan "$@"
    [[ "${#MODEL_ARGS[@]}" -eq 1 ]] || die "plan requires one bundle" 2
    section "Model Plan"
    catalog_python plan "${MODEL_ARGS[0]}"
    ;;
  download)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage download; exit 0; fi
    parse_optional_profile_args download "$@"
    [[ "${#MODEL_ARGS[@]}" -eq 1 ]] || die "download requires one bundle" 2
    download_bundle "${MODEL_ARGS[0]}"
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
