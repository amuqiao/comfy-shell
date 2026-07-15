#!/usr/bin/env bash
# check_env.sh - comfy-shell environment readiness report
#
# This is a read-only diagnostic script. It reports missing prerequisites and
# mismatches for the ComfyUI shell project; it never installs, downloads, or
# executes values from config files.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFY_DIR="$ROOT_DIR/ComfyUI"

usage() {
  cat <<'EOF'
用法:
  ./scripts/check_env.sh [--profile FILE] [--no-network]
  ./scripts/check_env.sh -h|--help

作用域:
  检测 comfy-shell / ComfyUI 的本地或服务器运行环境。覆盖仓库结构、配置、
  Python/uv、macOS MPS、Linux CUDA、PyTorch、模型目录、端口和基础网络连通性。

运行环境:
  Requires: Bash
  Optional: curl, git, uv, python3, lsof, nvidia-smi, nvcc, ffmpeg, tmux, conda
  macOS 会探测 Apple Silicon / MPS; Linux CUDA 配置会探测 NVIDIA 驱动。

不负责:
  不安装系统包,不创建 venv,不下载模型,不安装 custom_nodes,不启动 ComfyUI,
  不 source .env 或执行配置文件中的任意内容,不支持 Docker 检查。

配置:
  默认读取仓库根目录 .env。
  --profile FILE      显式指定其他配置文件。
  --no-network        跳过 PyPI / GitHub / HuggingFace 只读 HEAD 连通性探测。

默认行为:
  未传 --profile 时读取仓库根目录 .env。
  进程环境变量优先于配置文件值。
  默认会对 PyPI / GitHub / HuggingFace 执行只读 HEAD 探测。

输出:
  stdout 输出完整人读报告和结论。stderr 只输出参数错误。

成功标准:
  Exit Code 0 表示没有必要阻断项; 输出中仍可能包含 WARN/PENDING。
  Exit Code 1 表示存在必要项缺失, 或配置明确要求的设备不匹配。

副作用与保护边界:
  只读脚本, 不写文件, 不安装依赖, 不下载模型, 不启动进程。
  网络检查只使用 HEAD 探测; 使用 --no-network 可完全跳过。
  配置文件只按白名单键解析, 不执行其中内容。

常用示例:
  ./scripts/check_env.sh
  ./scripts/check_env.sh --no-network
  ./scripts/check_env.sh --profile configs/profiles/macos-mps.env.example

Exit Codes:
  0  必要基础项就绪,可能仍有 WARN/PENDING。
  1  存在必要项缺失或配置明确要求的设备不匹配。
  2  参数错误。
EOF
}

section() {
  printf '\n===== %s =====\n' "$1"
}

kv() {
  printf '%-28s %s\n' "$1:" "${2:-}"
}

event() {
  printf '%-10s %-18s %s\n' "$1" "$2" "${3:-}"
}

die_usage() {
  printf 'ERROR: %s\n' "$1" >&2
  usage >&2
  exit 2
}

MISSING_LABELS=()
MISSING_DETAILS=()
WARN_LABELS=()
WARN_DETAILS=()

note_missing() {
  MISSING_LABELS+=("$1")
  MISSING_DETAILS+=("$2")
}

note_warn() {
  WARN_LABELS+=("$1")
  WARN_DETAILS+=("$2")
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command_report() {
  local label="$1"
  local cmd="$2"
  local hint="$3"
  if command_exists "$cmd"; then
    event "OK" "$label" "$(command -v "$cmd")"
  else
    event "MISSING" "$label" "$cmd not found"
    note_missing "$label" "$hint"
  fi
}

info_command_version() {
  local label="$1"
  local cmd="$2"
  shift 2
  if command_exists "$cmd"; then
    printf '\n# %s\n$ %s' "$label" "$cmd"
    printf ' %s' "$@"
    printf '\n'
    "$cmd" "$@" 2>&1 | head -n 3 || true
  else
    printf '\n# %s\nMISSING: %s not found\n' "$label" "$cmd"
  fi
}

detect_os() {
  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin) printf macos ;;
    Linux) printf linux ;;
    *) printf other ;;
  esac
}

bytes_to_gib() {
  awk -v bytes="$1" 'BEGIN { printf "%.1f GiB", bytes / 1024 / 1024 / 1024 }'
}

resolve_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$ROOT_DIR" "$1" ;;
  esac
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

config_value() {
  local key="$1"
  local decl
  decl="$(declare -p "$key" 2>/dev/null || true)"
  if [[ "$decl" =~ ^declare\ -[^[:space:]]*x[^[:space:]]*\ $key(=|$) ]]; then
    printf '%s' "${!key}"
    return
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    env_value_from "$key" "$CONFIG_FILE"
  fi
}

is_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

disk_report_for_path() {
  local label="$1"
  local path="$2"
  local probe="$path"
  while [[ ! -e "$probe" && "$probe" != "/" ]]; do
    probe="$(dirname "$probe")"
  done
  if [[ -e "$probe" ]]; then
    printf '\n# %s\n$ df -h %s\n' "$label" "$probe"
    df -h "$probe" 2>&1 || true
    local avail_kib
    avail_kib="$(df -Pk "$probe" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
    if [[ -n "$avail_kib" && "$avail_kib" -lt 52428800 ]]; then
      note_warn "$label" "可用空间低于 50 GiB; AI 模型目录很快会占满磁盘"
    fi
  else
    event "WARN" "$label" "no existing parent for $path"
    note_warn "$label" "无法找到可用于 df 的已存在父目录: $path"
  fi
}

check_url() {
  local label="$1"
  local url="$2"
  printf '\n# %s\n$ curl -sS -I --max-time 8 %s\n' "$label" "$url"
  if command_exists curl; then
    curl -sS -I --max-time 8 "$url" 2>&1 | head -n 5 || true
  else
    printf 'SKIP: curl missing\n'
  fi
}

check_python_version() {
  if ! command_exists python3; then
    return
  fi
  local py_version
  py_version="$(python3 - <<'PY' 2>/dev/null || true
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
PY
)"
  if [[ -z "$py_version" ]]; then
    event "WARN" "python3" "unable to parse version"
    note_warn "python3" "无法解析 Python 版本"
    return
  fi
  event "OK" "python3-version" "$py_version"
  if ! python3 - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
  then
    note_warn "python3-version" "系统 python3 低于 3.10; 使用配置中的 COMFY_PYTHON 创建 .venv"
  fi
}

check_config() {
  section "CONFIG"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    event "MISSING" "config" "$CONFIG_FILE"
    note_missing "config" "配置文件不存在: $CONFIG_FILE"
    return
  fi

  event "OK" "config" "$CONFIG_FILE"
  COMFY_PROFILE="$(config_value COMFY_PROFILE)"
  COMFY_ENV_BACKEND="$(config_value COMFY_ENV_BACKEND)"
  COMFY_PYTHON="$(config_value COMFY_PYTHON)"
  COMFY_DEVICE="$(config_value COMFY_DEVICE)"
  COMFY_HOST="$(config_value COMFY_HOST)"
  COMFY_PORT="$(config_value COMFY_PORT)"
  COMFY_MODEL_ROOT="$(config_value COMFY_MODEL_ROOT)"
  COMFY_OUTPUT_ROOT="$(config_value COMFY_OUTPUT_ROOT)"
  CUDA_VISIBLE_DEVICES_VALUE="$(config_value CUDA_VISIBLE_DEVICES)"
  TORCH_PRE_VALUE="$(config_value TORCH_PRE)"
  TORCH_INDEX_URL_VALUE="$(config_value TORCH_INDEX_URL)"
  HF_ENDPOINT_VALUE="$(config_value HF_ENDPOINT)"

  kv "COMFY_PROFILE" "${COMFY_PROFILE:-MISSING}"
  kv "COMFY_ENV_BACKEND" "${COMFY_ENV_BACKEND:-MISSING}"
  kv "COMFY_PYTHON" "${COMFY_PYTHON:-MISSING}"
  kv "COMFY_DEVICE" "${COMFY_DEVICE:-MISSING}"
  kv "COMFY_HOST" "${COMFY_HOST:-MISSING}"
  kv "COMFY_PORT" "${COMFY_PORT:-MISSING}"
  kv "CUDA_VISIBLE_DEVICES" "${CUDA_VISIBLE_DEVICES_VALUE:-}"
  kv "TORCH_PRE" "${TORCH_PRE_VALUE:-}"
  kv "TORCH_INDEX_URL" "${TORCH_INDEX_URL_VALUE:-}"
  kv "HF_ENDPOINT" "${HF_ENDPOINT_VALUE:-}"

  [[ -n "$COMFY_PROFILE" ]] || note_missing "COMFY_PROFILE" "配置应声明 COMFY_PROFILE"
  [[ -n "$COMFY_PYTHON" ]] || note_missing "COMFY_PYTHON" "配置应声明 COMFY_PYTHON"
  [[ -n "$COMFY_HOST" ]] || note_missing "COMFY_HOST" "配置应声明 COMFY_HOST"
  [[ -n "$COMFY_PORT" ]] || note_missing "COMFY_PORT" "配置应声明 COMFY_PORT"
  [[ -n "$COMFY_MODEL_ROOT" ]] || note_missing "COMFY_MODEL_ROOT" "配置应声明 COMFY_MODEL_ROOT"
  [[ -n "$COMFY_OUTPUT_ROOT" ]] || note_missing "COMFY_OUTPUT_ROOT" "配置应声明 COMFY_OUTPUT_ROOT"
  case "${COMFY_ENV_BACKEND:-}" in
    uv) ;;
    conda) note_warn "COMFY_ENV_BACKEND" "conda 不是当前主线; 建议使用 uv" ;;
    "") note_missing "COMFY_ENV_BACKEND" "配置应声明 COMFY_ENV_BACKEND=uv" ;;
    *) note_missing "COMFY_ENV_BACKEND" "仅支持 uv 或 conda: ${COMFY_ENV_BACKEND}" ;;
  esac
  case "${COMFY_DEVICE:-}" in
    mps|cuda|cpu) ;;
    "") note_missing "COMFY_DEVICE" "配置应声明 COMFY_DEVICE=mps|cuda|cpu" ;;
    *) note_missing "COMFY_DEVICE" "未知 COMFY_DEVICE: ${COMFY_DEVICE}" ;;
  esac
  if [[ -n "${COMFY_PORT:-}" ]] && ! is_int "$COMFY_PORT"; then
    note_missing "COMFY_PORT" "COMFY_PORT 必须是数字: $COMFY_PORT"
  fi
  case "${COMFY_HOST:-}" in
    127.0.0.1|localhost|::1) ;;
    "") ;;
    *) note_missing "COMFY_HOST" "本阶段只允许本机 loopback host: ${COMFY_HOST}" ;;
  esac
}

check_repo() {
  section "COMFY-SHELL REPOSITORY"
  kv "ROOT_DIR" "$ROOT_DIR"
  kv "COMFY_DIR" "$COMFY_DIR"
  if [[ -f "$ROOT_DIR/.gitmodules" ]]; then
    event "OK" ".gitmodules" "present"
  else
    event "MISSING" ".gitmodules" "not found"
    note_missing ".gitmodules" "缺少子模块配置"
  fi
  if [[ -d "$COMFY_DIR" ]]; then
    event "OK" "ComfyUI" "directory present"
  else
    event "MISSING" "ComfyUI" "directory not found"
    note_missing "ComfyUI" "运行 git submodule update --init --recursive"
    return
  fi
  if [[ -f "$COMFY_DIR/main.py" ]]; then
    event "OK" "ComfyUI/main.py" "present"
  else
    note_missing "ComfyUI/main.py" "ComfyUI 子模块不完整"
  fi
  if [[ -f "$COMFY_DIR/requirements.txt" ]]; then
    event "OK" "requirements" "present"
  else
    note_missing "requirements" "ComfyUI requirements.txt 缺失"
  fi
  if [[ -f "$COMFY_DIR/pyproject.toml" ]]; then
    event "OK" "pyproject" "present"
  else
    note_warn "pyproject" "ComfyUI/pyproject.toml 缺失, 无法读取项目元数据"
  fi
  if git -C "$COMFY_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    event "OK" "ComfyUI-git" "$(git -C "$COMFY_DIR" rev-parse --short HEAD 2>/dev/null || true)"
  else
    event "MISSING" "ComfyUI-git" "not a git checkout"
    note_missing "ComfyUI-git" "ComfyUI 应作为 git submodule 存在"
  fi
  event "INFO" "Manager" "checked as Python package in PYTHON RUNTIME"
}

check_system() {
  local os_kind="$1"
  section "SYSTEM"
  kv "Generated at" "$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
  kv "Hostname" "$(hostname 2>/dev/null || printf UNKNOWN)"
  kv "User" "$(id -un 2>/dev/null || whoami 2>/dev/null || printf UNKNOWN)"
  kv "Shell" "${SHELL:-UNKNOWN}"
  kv "Platform" "$os_kind"
  kv "Arch" "$(uname -m 2>/dev/null || printf UNKNOWN)"
  if [[ "$os_kind" == "macos" ]]; then
    kv "macOS" "$(sw_vers -productVersion 2>/dev/null || printf UNKNOWN)"
    kv "Build" "$(sw_vers -buildVersion 2>/dev/null || printf UNKNOWN)"
    kv "CPU" "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || printf UNKNOWN)"
    local mem_bytes
    mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
    [[ -n "$mem_bytes" ]] && kv "Memory" "$(bytes_to_gib "$mem_bytes")"
  elif [[ "$os_kind" == "linux" ]]; then
    if [[ -r /etc/os-release ]]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      kv "Distribution" "${PRETTY_NAME:-UNKNOWN}"
    fi
    kv "Kernel" "$(uname -r 2>/dev/null || printf UNKNOWN)"
    kv "CPU cores" "$(command_exists nproc && nproc || printf UNKNOWN)"
    if [[ -r /proc/meminfo ]]; then
      local mem_kib
      mem_kib="$(awk '/MemTotal:/ {print $2}' /proc/meminfo || true)"
      [[ -n "$mem_kib" ]] && kv "Memory" "$(bytes_to_gib "$((mem_kib * 1024))")"
    fi
  fi
  disk_report_for_path "root disk" "/"
  disk_report_for_path "repo disk" "$ROOT_DIR"
}

check_tools() {
  section "BASE TOOLS"
  require_command_report "git" git "安装 git"
  require_command_report "curl" curl "安装 curl"
  if command_exists python3; then
    event "OK" "python3" "$(command -v python3)"
  else
    event "WARN" "python3" "not found"
    note_warn "python3" "未找到系统 python3; uv 可管理 Python, 但部分辅助脚本可能仍需要 python3"
  fi
  check_python_version
  if [[ "${COMFY_ENV_BACKEND:-uv}" == "uv" || -z "${COMFY_ENV_BACKEND:-}" ]]; then
    require_command_report "uv" uv "安装 uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
  else
    info_command_version "uv (optional)" uv --version
  fi
  info_command_version "ffmpeg (recommended for video/audio workflows)" ffmpeg -version
  info_command_version "tmux (recommended on servers)" tmux -V
  info_command_version "conda (info only)" conda --version
}

check_acceleration() {
  local os_kind="$1"
  section "ACCELERATION"
  case "${COMFY_DEVICE:-}" in
    mps)
      if [[ "$os_kind" == "macos" && "$(uname -m 2>/dev/null || true)" == "arm64" ]]; then
        event "OK" "mps-host" "macOS Apple Silicon"
      else
        event "MISSING" "mps-host" "COMFY_DEVICE=mps requires Apple Silicon macOS"
        note_missing "mps-host" "mps 配置只能用于 Apple Silicon macOS"
      fi
      ;;
    cuda)
      if [[ "$os_kind" != "linux" ]]; then
        event "MISSING" "cuda-host" "COMFY_DEVICE=cuda expects Linux NVIDIA host"
        note_missing "cuda-host" "cuda 配置应用于 Linux NVIDIA 服务器"
      fi
      if command_exists nvidia-smi; then
        info_command_version "nvidia-smi" nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
        local driver_cuda
        driver_cuda="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([^ |]*\).*/\1/p' | head -n 1 || true)"
        kv "Driver CUDA max" "${driver_cuda:-UNKNOWN}"
      else
        event "MISSING" "nvidia-smi" "not found"
        note_missing "nvidia-smi" "CUDA 配置需要 NVIDIA 驱动和 nvidia-smi"
      fi
      info_command_version "nvcc (optional)" nvcc --version
      ;;
    cpu|"")
      event "INFO" "device" "${COMFY_DEVICE:-not set}"
      ;;
  esac
}

check_python_runtime() {
  section "PYTHON RUNTIME"
  local runtime_python=""
  local project_env_ready=0
  if [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    runtime_python="$ROOT_DIR/.venv/bin/python"
    project_env_ready=1
    event "OK" ".venv" "$runtime_python"
  else
    event "PENDING" ".venv" "not created at $ROOT_DIR/.venv"
  fi
  if [[ -z "$runtime_python" && -x "$COMFY_DIR/venv/bin/python" ]]; then
    runtime_python="$COMFY_DIR/venv/bin/python"
    event "WARN" "ComfyUI/venv" "$runtime_python"
    note_warn "venv-location" "检测到 ComfyUI/venv, 但壳脚本只使用仓库根目录 .venv; 请运行 ./scripts/local.sh bootstrap"
  fi
  [[ -n "$runtime_python" ]] || runtime_python="$(command -v python3 2>/dev/null || true)"
  if [[ -z "$runtime_python" ]]; then
    event "SKIP" "torch" "python3 missing"
    return
  fi
  kv "Runtime python" "$runtime_python"
  local torch_report
  torch_report="$("$runtime_python" - <<'PY' 2>&1 || true
import platform
print("python:", platform.python_version())
try:
    import torch
except Exception as exc:
    print("torch.import: missing")
    print("torch.error:", exc)
else:
    print("torch.import: ok")
    print("torch:", torch.__version__)
    print("torch.cuda.available:", torch.cuda.is_available())
    print("torch.cuda.version:", getattr(torch.version, "cuda", None))
    try:
        print("torch.mps.available:", torch.backends.mps.is_available())
        print("torch.mps.built:", torch.backends.mps.is_built())
    except Exception as exc:
        print("torch.mps: unavailable:", exc)
PY
)"
  printf '%s\n' "$torch_report"
  if ! printf '%s\n' "$torch_report" | grep -q '^torch.import: ok$'; then
    if [[ "$project_env_ready" -eq 1 ]]; then
      note_missing "torch" "项目 Python 环境已存在, 但 torch 无法导入"
    else
      note_warn "torch" "项目 .venv 尚未创建; bootstrap 后再检查 torch 后端"
    fi
  elif [[ "$project_env_ready" -eq 1 ]]; then
    case "${COMFY_DEVICE:-}" in
      mps)
        if ! printf '%s\n' "$torch_report" | grep -q '^torch.mps.available: True$'; then
          note_missing "torch-mps" "COMFY_DEVICE=mps, 但项目 torch 未报告 MPS available"
        fi
        ;;
      cuda)
        if ! printf '%s\n' "$torch_report" | grep -q '^torch.cuda.available: True$'; then
          note_missing "torch-cuda" "COMFY_DEVICE=cuda, 但项目 torch 未报告 CUDA available"
        fi
        ;;
    esac
  else
    note_warn "torch-backend" "尚未创建项目 .venv; 当前 torch 后端结果只代表 fallback Python"
  fi
  if [[ "$project_env_ready" -eq 1 ]]; then
    if PYTHONPATH="$COMFY_DIR${PYTHONPATH:+:$PYTHONPATH}" "$runtime_python" - <<'PY' >/dev/null 2>&1
import comfyui_manager
if not comfyui_manager.__file__ or not comfyui_manager.__file__.endswith("__init__.py"):
    raise SystemExit(1)
PY
    then
      event "OK" "manager-package" "comfyui_manager importable"
    else
      note_missing "manager-package" "项目 .venv 在 ComfyUI runtime 中无法导入 comfyui_manager; 运行 ./scripts/nodes.sh status"
    fi
  else
    note_warn "manager-package" "项目 .venv 尚未创建; bootstrap 后再检查 comfyui_manager"
  fi
  printf '\n# Key package imports\n'
  "$runtime_python" - <<'PY' 2>&1 || true
packages = [
    ("torchvision", "torchvision"),
    ("torchaudio", "torchaudio"),
    ("numpy", "numpy"),
    ("PIL", "Pillow"),
    ("aiohttp", "aiohttp"),
    ("yaml", "PyYAML"),
    ("safetensors", "safetensors"),
]
for module, label in packages:
    try:
        imported = __import__(module)
    except Exception as exc:
        print(f"{label}: MISSING or import failed: {exc}")
    else:
        print(f"{label}: {getattr(imported, '__version__', 'present')}")
PY
}

check_paths_and_port() {
  section "PATHS / PORT"
  local model_root="${COMFY_MODEL_ROOT:-}"
  local output_root="${COMFY_OUTPUT_ROOT:-}"
  if [[ -z "$model_root" || -z "$output_root" ]]; then
    event "SKIP" "paths" "COMFY_MODEL_ROOT or COMFY_OUTPUT_ROOT missing"
    return
  fi
  local model_abs
  local output_abs
  model_abs="$(resolve_path "$model_root")"
  output_abs="$(resolve_path "$output_root")"
  kv "Model root" "$model_abs"
  kv "Output root" "$output_abs"
  disk_report_for_path "model disk" "$model_abs"
  disk_report_for_path "output disk" "$output_abs"
  if [[ -d "$model_abs" ]]; then
    event "OK" "model-root" "exists"
  else
    event "PENDING" "model-root" "directory not created"
  fi
  if [[ -w "$(dirname "$model_abs")" ]] 2>/dev/null; then
    event "OK" "model-parent" "writable"
  else
    note_warn "model-parent" "模型目录父目录可能不可写: $(dirname "$model_abs")"
  fi
  if [[ -d "$output_abs" ]]; then
    event "OK" "output-root" "exists"
  else
    event "PENDING" "output-root" "directory not created"
  fi
  if [[ -w "$(dirname "$output_abs")" ]] 2>/dev/null; then
    event "OK" "output-parent" "writable"
  else
    note_warn "output-parent" "输出目录父目录可能不可写: $(dirname "$output_abs")"
  fi
  local comfy_path
  for comfy_path in "$COMFY_DIR/custom_nodes" "$COMFY_DIR/input" "$COMFY_DIR/output" "$COMFY_DIR/user" "$COMFY_DIR/temp"; do
    if [[ -d "$comfy_path" ]]; then
      local perms=""
      [[ -r "$comfy_path" ]] && perms="${perms}r"
      [[ -w "$comfy_path" ]] && perms="${perms}w"
      [[ -x "$comfy_path" ]] && perms="${perms}x"
      event "OK" "${comfy_path#"$COMFY_DIR"/}" "exists perms=${perms:-none}"
    else
      event "PENDING" "${comfy_path#"$COMFY_DIR"/}" "directory not created"
    fi
  done
  if [[ -f "$COMFY_DIR/extra_model_paths.yaml" ]]; then
    event "OK" "extra-models" "extra_model_paths.yaml"
  elif [[ -f "$COMFY_DIR/extra_model_paths.yaml.example" ]]; then
    event "PENDING" "extra-models" "only extra_model_paths.yaml.example"
  fi

  section "MODEL INVENTORY"
  local bucket
  local count
  for bucket in checkpoints diffusion_models vae loras controlnet clip text_encoders unet; do
    if [[ -d "$model_abs/$bucket" ]]; then
      count="$(find "$model_abs/$bucket" -maxdepth 1 -type f \( -name '*.safetensors' -o -name '*.ckpt' -o -name '*.pt' -o -name '*.pth' -o -name '*.bin' -o -name '*.gguf' \) 2>/dev/null | wc -l | tr -d ' ')"
      event "INFO" "$bucket" "${count} model files"
    else
      event "PENDING" "$bucket" "directory missing"
    fi
  done

  local host="${COMFY_HOST:-}"
  local port="${COMFY_PORT:-}"
  if [[ -z "$host" || -z "$port" ]]; then
    event "SKIP" "port" "COMFY_HOST or COMFY_PORT missing"
    return
  fi
  kv "ComfyUI URL" "http://${host}:${port}"
  if command_exists lsof; then
    local owner
    owner="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1 " pid=" $2}' || true)"
    if [[ -n "$owner" ]]; then
      event "INFO" "port-$port" "in use by $owner"
    else
      event "OK" "port-$port" "free"
    fi
  else
    event "WARN" "lsof" "not available; skip port owner check"
  fi

  if command_exists curl; then
    printf '\n# ComfyUI API probe\n$ curl -fsS --max-time 2 http://%s:%s/system_stats\n' "$host" "$port"
    if curl -fsS --max-time 2 "http://${host}:${port}/system_stats" >/dev/null 2>&1; then
      event "OK" "system_stats" "ComfyUI is responding"
    else
      event "PENDING" "system_stats" "ComfyUI not running or not reachable"
    fi
  fi
}

check_network() {
  [[ "$NO_NETWORK" == "1" ]] && { section "NETWORK"; event "SKIP" "network" "--no-network"; return; }
  section "NETWORK"
  check_url "PyPI" "https://pypi.org/simple/"
  check_url "GitHub" "https://github.com"
  check_url "HuggingFace" "https://huggingface.co"
  if [[ -n "${HF_ENDPOINT_VALUE:-}" ]]; then
    check_url "HF_ENDPOINT" "$HF_ENDPOINT_VALUE"
  fi
}

print_result() {
  section "RESULT"
  local idx
  if [[ "${#WARN_LABELS[@]}" -gt 0 ]]; then
    printf 'WARN/PENDING:\n'
    idx=0
    while [[ "$idx" -lt "${#WARN_LABELS[@]}" ]]; do
      printf '%s: %s\n' "- ${WARN_LABELS[$idx]}" "${WARN_DETAILS[$idx]}"
      idx=$((idx + 1))
    done
    printf '\n'
  fi
  if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
    printf '未发现 blocker。若仍有 PENDING,请按阶段继续 bootstrap / start ComfyUI。\n'
    return 0
  fi
  printf '检测到 %d 项必要问题:\n' "${#MISSING_LABELS[@]}"
  idx=0
  while [[ "$idx" -lt "${#MISSING_LABELS[@]}" ]]; do
    printf '%s: %s\n' "- ${MISSING_LABELS[$idx]}" "${MISSING_DETAILS[$idx]}"
    idx=$((idx + 1))
  done
  return 1
}

CONFIG_FILE="$ROOT_DIR/.env"
NO_NETWORK=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ "$#" -ge 2 ]] || die_usage "--profile requires a file"
      CONFIG_FILE="$(resolve_path "$2")"
      shift 2
      ;;
    --profile=*)
      CONFIG_FILE="$(resolve_path "${1#--profile=}")"
      shift
      ;;
    --no-network)
      NO_NETWORK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die_usage "unknown argument: $1"
      ;;
  esac
done

OS_KIND="$(detect_os)"

check_config
check_system "$OS_KIND"
check_repo
check_tools
check_acceleration "$OS_KIND"
check_python_runtime
check_paths_and_port
check_network
print_result
