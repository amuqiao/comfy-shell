#!/usr/bin/env bash
# env.sh - activate and inspect comfy-shell local profiles

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/configs/profiles"
ENV_FILE="$ROOT_DIR/.env"

usage() {
  cat <<'EOF'
用法:
  ./scripts/env.sh <command> [args...]
  ./scripts/env.sh -h|--help

作用域:
  管理 comfy-shell 的本地 profile 激活和只读查看。
  profile 是配置数据, 不是 shell 脚本; 本脚本不会 source 或执行 profile 内容。

运行环境:
  Requires: Bash, cp, find
  Profile directory: configs/profiles
  Active env file: .env

命令:
  profiles            列出 configs/profiles 下可用 profile
  use <profile>       激活 profile, 写入 .env
  show                显示当前 .env 关键配置
  help                显示本帮助

不负责:
  不安装依赖,不启动 ComfyUI,不下载模型,不读取或输出 secret。

输出:
  profiles: PROFILE 行, 包含 profile 名、device、backend 和来源文件。
  use: Activated 结果和下一步 check 命令。
  show: 当前 .env 的白名单配置键。

副作用与保护边界:
  profiles/show 只读。
  use 会用 configs/profiles/<profile>.env.example 覆盖仓库根目录 .env。
  profile 名只允许简单文件名, 不允许路径片段。
  .env 不应提交到 git。

常用示例:
  ./scripts/env.sh profiles
  ./scripts/env.sh use macos-mps
  ./scripts/env.sh show

Exit Codes:
  0  成功
  2  缺少 command、非法参数、profile 不存在或 .env 不存在
EOF
}

command_usage() {
  local name="$1"
  case "$name" in
    profiles)
      cat <<'EOF'
用法:
  ./scripts/env.sh profiles
  ./scripts/env.sh profiles -h|--help

作用域:
  只读列出 configs/profiles 下的 *.env.example。

输出:
  每个 profile 一行, 包含名称、COMFY_DEVICE、COMFY_ENV_BACKEND 和相对路径。

常用示例:
  ./scripts/env.sh profiles
EOF
      ;;
    use)
      cat <<'EOF'
用法:
  ./scripts/env.sh use <profile>
  ./scripts/env.sh use -h|--help

作用域:
  将 configs/profiles/<profile>.env.example 复制为仓库根目录 .env。

副作用与保护边界:
  会覆盖 .env。
  不会安装依赖、下载模型或启动 ComfyUI。
  不会执行 profile 内容。

常用示例:
  ./scripts/env.sh use macos-mps
  ./scripts/env.sh use server-cuda-a10
  ./scripts/check_env.sh
EOF
      ;;
    show)
      cat <<'EOF'
用法:
  ./scripts/env.sh show
  ./scripts/env.sh show -h|--help

作用域:
  只读显示当前 .env 中的白名单配置键。

输出:
  COMFY_PROFILE、COMFY_DEVICE、COMFY_HOST、COMFY_PORT、TORCH_INDEX_URL 等
  与本项目脚本相关的键。不输出 secret。

常用示例:
  ./scripts/env.sh show
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
  printf '%-10s %-18s %s\n' "$1" "$2" "${3:-}"
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

profile_path() {
  local name="$1"
  case "$name" in
    */*|.*|'') die "profile name must be a simple name, got: $name" 2 ;;
  esac
  printf '%s/%s.env.example' "$PROFILE_DIR" "$name"
}

list_profiles() {
  section "Profiles"
  if [[ ! -d "$PROFILE_DIR" ]]; then
    die "$PROFILE_DIR not found" 2
  fi
  local path
  local name
  local device
  local backend
  while IFS= read -r path; do
    name="$(basename "$path" .env.example)"
    device="$(env_value_from COMFY_DEVICE "$path")"
    backend="$(env_value_from COMFY_ENV_BACKEND "$path")"
    event "PROFILE" "$name" "device=${device:-unknown} backend=${backend:-unknown} file=${path#$ROOT_DIR/}"
  done < <(find "$PROFILE_DIR" -maxdepth 1 -type f -name '*.env.example' | sort)
}

use_profile() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "use requires profile name" 2
  local src
  src="$(profile_path "$name")"
  [[ -f "$src" ]] || die "profile not found: ${src#$ROOT_DIR/}" 2
  cp "$src" "$ENV_FILE"
  section "Activated"
  event "OK" "$name" ".env <- ${src#$ROOT_DIR/}"
  event "NEXT" "check" "./scripts/check_env.sh"
}

show_env() {
  section "Current Env"
  [[ -f "$ENV_FILE" ]] || die ".env not found; run ./scripts/env.sh use <profile>" 2
  local key
  for key in COMFY_PROFILE COMFY_ENV_BACKEND COMFY_PYTHON COMFY_DEVICE COMFY_HOST COMFY_PORT CUDA_VISIBLE_DEVICES TORCH_PRE TORCH_INDEX_URL HF_ENDPOINT COMFY_MODEL_ROOT COMFY_OUTPUT_ROOT; do
    event "ENV" "$key" "$(env_value_from "$key" "$ENV_FILE")"
  done
}

command="${1:-}"
case "$command" in
  -h|--help|help)
    usage
    ;;
  profiles)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage profiles; exit 0; fi
    [[ "$#" -eq 0 ]] || die "profiles takes no arguments" 2
    list_profiles
    ;;
  use)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage use; exit 0; fi
    [[ "$#" -eq 1 ]] || die "use requires exactly one profile name" 2
    use_profile "${1:-}"
    ;;
  show)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage show; exit 0; fi
    [[ "$#" -eq 0 ]] || die "show takes no arguments" 2
    show_env
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
