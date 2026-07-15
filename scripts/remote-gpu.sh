#!/usr/bin/env bash
# remote-gpu.sh - read-only GPU status for an SSH target

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DEFAULT_CONNECT_TIMEOUT="10"

usage() {
  cat <<'EOF'
用法:
  ./scripts/remote-gpu.sh status --host USER@HOST [--connect-timeout SECONDS] [--json]
  ./scripts/remote-gpu.sh -h|--help

职责:
  只读查询远端主机的 GPU 概览和 GPU 计算进程。

不负责:
  不启动、停止、重启或检查任何业务服务。
  不管理容器、端口、进程生命周期或远端文件。

运行环境:
  Local: Bash, ssh, python3
  Remote: nvidia-smi must be installed and executable by the SSH user.

选项:
  --host USER@HOST           必填, 远端 SSH 目标。
  --connect-timeout SECONDS  SSH 连接超时, 默认 10; 可用 REMOTE_GPU_CONNECT_TIMEOUT 覆盖。
  --json                     stdout 只输出单个 JSON 文档。

输出:
  默认 stdout 输出摘要、按 GPU 分组的资源状态, 以及关联到 GPU index 的进程。
  --json 时 stdout 只输出单个 JSON 文档, 包含 host、gpus 和 processes。
  错误、非法参数和 ssh/nvidia-smi 诊断输出到 stderr。

副作用与保护边界:
  只执行只读 nvidia-smi 查询; 不写入本地或远端状态, 不启动、停止或修改远端资源。

常用示例:
  ./scripts/remote-gpu.sh status --host user@example.com
  ./scripts/remote-gpu.sh status --host user@example.com --connect-timeout 5
  ./scripts/remote-gpu.sh status --host user@example.com --json

Exit Codes:
  0  查询成功。
  1  查询成功但 GPU 概览为空。
  2  参数、用法、配置或前置条件错误, 例如缺少 ssh、python3 或远端 nvidia-smi。
  4  本地格式化远端 nvidia-smi 快照失败。
  其他非 0 由 ssh 或 nvidia-smi 透传。
EOF
}

validate_remote_host() {
  local value="$1"
  [[ "$value" == *@* ]] || usage_error "--host must use USER@HOST" usage
  [[ "$value" != -* && "$value" != *[[:space:]]* ]] || usage_error "--host contains invalid characters: $value" usage
}

validate_positive_uint() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 ]] || usage_error "$label must be a positive integer" usage
}

remote_cmd() {
  local remote_command="$1"
  ssh -o ConnectTimeout="$connect_timeout" "$host" "$remote_command"
}

remote_snapshot() {
  remote_cmd "command -v nvidia-smi >/dev/null 2>&1 || { printf 'ERROR: missing required command: nvidia-smi\n' >&2; exit 2; }; printf '%s\n' __REMOTE_GPU_SUMMARY__; nvidia-smi --query-gpu=index,uuid,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,power.limit,compute_mode,driver_version --format=csv,noheader,nounits; printf '%s\n' __REMOTE_GPU_PROCESSES__; nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits"
}

print_status() {
  local snapshot
  local output_args

  snapshot="$(remote_snapshot)"
  output_args=("${ROOT_DIR}/scripts/lib/remote_gpu_format.py" --host "$host")
  if [[ "$json_output" == true ]]; then
    output_args+=(--json)
  fi

  printf '%s\n' "$snapshot" | python3 "${output_args[@]}"
}

cmd="${1:-}"
case "$cmd" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
esac
shift

case "$cmd" in
  status)
    host=""
    connect_timeout="${REMOTE_GPU_CONNECT_TIMEOUT:-$DEFAULT_CONNECT_TIMEOUT}"
    json_output=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
          host="$2"
          shift 2
          ;;
        --connect-timeout)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--connect-timeout requires a value" usage
          connect_timeout="$2"
          shift 2
          ;;
        --json)
          json_output=true
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown status option: $1" usage
          ;;
      esac
    done

    [[ -n "$host" ]] || usage_error "--host is required" usage
    validate_remote_host "$host"
    validate_positive_uint "--connect-timeout" "$connect_timeout"
    require_cmd ssh
    require_cmd python3
    print_status
    ;;
  *)
    usage_error "unknown command: $cmd" usage
    ;;
esac
