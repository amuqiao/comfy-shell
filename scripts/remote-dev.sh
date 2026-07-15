#!/usr/bin/env bash
# remote-dev.sh - fixed remote development target for this project

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REMOTE_HOST="wangqiao@47.94.108.140"
REMOTE_DIR="/data/wangqiao/comfy-shell"
REMOTE_PROFILE="server-cuda-a10"
HEALTH_URL="http://127.0.0.1:8188"
DEFAULT_LOG_TAIL="200"

usage() {
  cat <<'EOF'
用法:
  ./scripts/remote-dev.sh sync --yes [--delete]
  ./scripts/remote-dev.sh bootstrap --yes [--uv-index-url URL]
  ./scripts/remote-dev.sh start --yes
  ./scripts/remote-dev.sh stop --yes
  ./scripts/remote-dev.sh restart --yes
  ./scripts/remote-dev.sh status
  ./scripts/remote-dev.sh logs [--tail N|all] [--follow]
  ./scripts/remote-dev.sh tunnel [--local-port PORT] [--dry-run]
  ./scripts/remote-dev.sh gpu [--json]
  ./scripts/remote-dev.sh -h|--help

作用域:
  管理固定远程开发服务器上的 comfy-shell checkout。这个入口只保存项目默认目标,
  具体远端动作委托给可复用的 ./scripts/remote.sh 和 ./scripts/remote-gpu.sh。

固定配置:
  host     wangqiao@47.94.108.140
  dir      /data/wangqiao/comfy-shell
  profile  server-cuda-a10
  health   http://127.0.0.1:8188/system_stats

不负责:
  不接受 host/dir 覆盖; 需要自定义远端目标时使用 ./scripts/remote.sh。
  不管理 Docker、systemd、第三方 custom_nodes、模型自动下载或公网端口暴露。

输出:
  status 输出远端 ComfyUI 状态、健康检查和 GPU 状态。
  logs 输出远端日志; --follow 会保持 SSH 前台连接。
  tunnel 输出端口映射并保持 SSH 前台连接。

副作用与保护边界:
  sync --yes 会上传本地 checkout 到固定远端目录。
  bootstrap --yes 会在远端写 .env、.venv、.run/、logs/ 并访问 Python 包索引。
  start/stop/restart --yes 会在远端启动或停止 ComfyUI 进程。
  tunnel 会占用本地端口, 不修改远端文件。

常用示例:
  ./scripts/remote-dev.sh sync --yes
  ./scripts/remote-dev.sh bootstrap --yes
  ./scripts/remote-dev.sh start --yes
  ./scripts/remote-dev.sh status
  ./scripts/remote-dev.sh logs --tail 200
  ./scripts/remote-dev.sh tunnel

Exit Codes:
  0  成功。
  1  健康检查未就绪, 或远端 dev.sh 正常执行但业务状态未满足。
  2  参数、用法、配置或前置条件错误。
  3  入口保护拒绝继续。
  4  入口自身发起运行后的外部依赖、网络或文件产物失败。
  其他非 0 由 ssh、rsync、远端脚本或 remote-gpu.sh 透传。
EOF
}

print_target() {
  printf '远程开发环境: %s\n' "$REMOTE_HOST"
  printf '项目目录: %s\n' "$REMOTE_DIR"
  printf 'Profile: %s\n' "$REMOTE_PROFILE"
}

validate_tail() {
  local value="$1"
  [[ "$value" == "all" || "$value" =~ ^[0-9]+$ ]] || usage_error "--tail must be a non-negative integer or all" usage
}

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 && "$value" -le 65535 ]] || usage_error "--local-port must be a port between 1 and 65535" usage
}

require_yes() {
  local confirmed="$1"
  [[ "$confirmed" == true ]] || usage_error "remote write/lifecycle command requires --yes" usage
}

ready_code() {
  "${ROOT_DIR}/scripts/remote.sh" ready --host "$REMOTE_HOST" --url "$HEALTH_URL"
}

print_ready_code() {
  local code
  local status
  set +e
  code="$(ready_code)"
  status=$?
  set -e
  printf '%s\n' "${code:-000}"
  return "$status"
}

wait_ready() {
  local code
  local attempt
  for attempt in {1..90}; do
    set +e
    code="$(ready_code)"
    status=$?
    set -e
    if [[ "$status" -eq 0 && "$code" == "200" ]]; then
      printf '服务已就绪: HTTP %s\n' "$code"
      return 0
    fi
    if [[ "$status" -ne 1 ]]; then
      printf '健康检查运行失败: exit=%s, code=%s\n' "$status" "${code:-000}" >&2
      return "$status"
    fi
    printf '等待服务就绪: HTTP %s (%s/90)\n' "${code:-000}" "$attempt"
    sleep 1
  done
  printf '服务未在预期时间内就绪, 请查看日志:\n' >&2
  printf '  ./scripts/remote-dev.sh logs --tail 200\n' >&2
  return 1
}

show_status() {
  print_target
  printf '\n===== ComfyUI =====\n'
  "${ROOT_DIR}/scripts/remote.sh" status --host "$REMOTE_HOST" --dir "$REMOTE_DIR"
  printf '\n===== Health =====\n'
  print_ready_code || true
  printf '\n===== GPU =====\n'
  set +e
  "${ROOT_DIR}/scripts/remote-gpu.sh" status --host "$REMOTE_HOST"
  gpu_status=$?
  set -e
  if [[ "$gpu_status" -ne 0 ]]; then
    event "WARN" "remote-gpu" "status failed exit=$gpu_status"
  fi
}

cmd="${1:-}"
case "$cmd" in
  -h|--help)
    usage
    exit 0
    ;;
  sync)
    shift
    delete_arg=()
    yes=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --delete)
          delete_arg+=(--delete)
          shift
          ;;
        --yes)
          yes=true
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown sync option: $1" usage
          ;;
      esac
    done
    require_yes "$yes"
    print_target
    exec "${ROOT_DIR}/scripts/remote.sh" sync --host "$REMOTE_HOST" --dir "$REMOTE_DIR" --yes "${delete_arg[@]}"
    ;;
  bootstrap)
    shift
    uv_index_url=""
    yes=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --uv-index-url)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--uv-index-url requires a value" usage
          uv_index_url="$2"
          shift 2
          ;;
        --yes)
          yes=true
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown bootstrap option: $1" usage
          ;;
      esac
    done
    require_yes "$yes"
    print_target
    if [[ -n "$uv_index_url" ]]; then
      exec "${ROOT_DIR}/scripts/remote.sh" bootstrap --host "$REMOTE_HOST" --dir "$REMOTE_DIR" --profile "$REMOTE_PROFILE" --uv-index-url "$uv_index_url" --yes
    fi
    exec "${ROOT_DIR}/scripts/remote.sh" bootstrap --host "$REMOTE_HOST" --dir "$REMOTE_DIR" --profile "$REMOTE_PROFILE" --yes
    ;;
  start)
    shift
    yes=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --yes)
          yes=true
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown start option: $1" usage
          ;;
      esac
    done
    require_yes "$yes"
    print_target
    "${ROOT_DIR}/scripts/remote.sh" start --host "$REMOTE_HOST" --dir "$REMOTE_DIR" --yes
    wait_ready
    printf '\n'
    show_status
    ;;
  stop|restart)
    shift
    yes=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --yes)
          yes=true
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown ${cmd} option: $1" usage
          ;;
      esac
    done
    require_yes "$yes"
    print_target
    "${ROOT_DIR}/scripts/remote.sh" "$cmd" --host "$REMOTE_HOST" --dir "$REMOTE_DIR" --yes
    printf '\n'
    show_status
    ;;
  status)
    shift
    [[ "$#" -eq 0 ]] || usage_error "status takes no arguments" usage
    show_status
    ;;
  logs)
    shift
    tail_lines="$DEFAULT_LOG_TAIL"
    follow=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --tail)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--tail requires a value" usage
          tail_lines="$2"
          shift 2
          ;;
        --follow)
          follow=true
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown logs option: $1" usage
          ;;
      esac
    done
    validate_tail "$tail_lines"
    args=(logs --host "$REMOTE_HOST" --dir "$REMOTE_DIR" --tail "$tail_lines")
    if [[ "$follow" == true ]]; then
      args+=(--follow)
    fi
    exec "${ROOT_DIR}/scripts/remote.sh" "${args[@]}"
    ;;
  tunnel)
    shift
    local_port="8188"
    dry_run=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --local-port)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--local-port requires a value" usage
          local_port="$2"
          shift 2
          ;;
        --dry-run)
          dry_run=true
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown tunnel option: $1" usage
          ;;
      esac
    done
    validate_port "$local_port"
    args=(tunnel --host "$REMOTE_HOST" --local-port "$local_port" --remote-port 8188)
    if [[ "$dry_run" == true ]]; then
      args+=(--dry-run)
    fi
    exec "${ROOT_DIR}/scripts/remote.sh" "${args[@]}"
    ;;
  gpu)
    shift
    json_arg=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json)
          json_arg+=(--json)
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown gpu option: $1" usage
          ;;
      esac
    done
    exec "${ROOT_DIR}/scripts/remote-gpu.sh" status --host "$REMOTE_HOST" "${json_arg[@]}"
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    usage_error "unknown command: $cmd" usage
    ;;
esac
