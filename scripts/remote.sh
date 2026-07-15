#!/usr/bin/env bash
# remote.sh - SSH orchestration for explicit remote hosts

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DEFAULT_READY_URL="http://127.0.0.1:8188"
DEFAULT_LOCAL_PORT="8188"
DEFAULT_REMOTE_HOST="127.0.0.1"
DEFAULT_REMOTE_PORT="8188"
DEFAULT_LOG_TAIL="200"
DEFAULT_CONNECT_TIMEOUT="10"

usage() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh sync --yes [options]
  ./scripts/remote.sh bootstrap --yes [options]
  ./scripts/remote.sh start --yes [options]
  ./scripts/remote.sh stop --yes [options]
  ./scripts/remote.sh restart --yes [options]
  ./scripts/remote.sh status [options]
  ./scripts/remote.sh logs [--tail N|all] [--follow] [options]
  ./scripts/remote.sh ready [--url URL] [options]
  ./scripts/remote.sh tunnel [--local-port PORT] [--remote-host HOST] [--remote-port PORT] [--dry-run] [options]
  ./scripts/remote.sh gpu [--connect-timeout SECONDS] [--json] [options]
  ./scripts/remote.sh -h|--help
  ./scripts/remote.sh <command> -h|--help

作用域:
  唯一远端入口。负责从本机通过 SSH/rsync 编排远端 comfy-shell checkout:
  同步代码、执行远端 checkout 内的 local.sh 生命周期、查看日志、健康检查、SSH 隧道和 GPU 只读诊断。

不负责:
  不管理 Docker、systemd、第三方 custom_nodes、模型自动下载或公网端口暴露。
  不读取远端 secret, 不执行自由 shell 片段, 不提供兼容 wrapper。

配置与环境变量:
  无 --host/--dir 的命令读取仓库根目录 .env 中的真实远端目标:
    REMOTE_HOST=wangqiao@47.94.108.140
    REMOTE_DIR=/data/wangqiao/comfy-shell
  默认读取仓库根目录 .env 的 REMOTE_* 键; 已导出的同名环境变量优先。
  CLI 参数只覆盖本次调用: --profile、--host、--dir、--url、--local-port、--remote-port。
  --profile FILE 指定本机 remote.sh 本次读取的配置文件。
  远端 local.sh 默认读取远端 checkout 根目录 .env。

副作用与保护边界:
  sync/bootstrap/start/stop/restart 必须显式传 --yes。
  sync --yes 会创建远端目录并上传本地 checkout; --delete 会删除远端多余的非排除文件。
  bootstrap --yes 会在远端写 .venv、.run/、logs/ 并访问 Python 包索引。
  start/stop/restart --yes 会在远端启动或停止 ComfyUI 进程。
  status/logs/ready/gpu 只读; tunnel 只占用本地端口并保持 SSH 前台进程。

输出:
  stdout 输出命令、远端脚本结果、日志、健康检查 HTTP code、隧道命令或 GPU 状态。
  gpu --json 时 stdout 只输出单个 JSON 文档。
  stderr 输出参数错误、缺少依赖、ssh/rsync/curl/nvidia-smi 诊断。

常用示例:
  # 首次或 .env 缺 REMOTE_* 时, 先把 .env.example 中的 REMOTE_* 合并到 .env。
  ./scripts/remote.sh sync --yes
  ./scripts/remote.sh bootstrap --yes
  ./scripts/remote.sh start --yes
  ./scripts/remote.sh restart --yes
  ./scripts/remote.sh stop --yes
  ./scripts/remote.sh status
  ./scripts/remote.sh logs --tail 200
  ./scripts/remote.sh tunnel
  ./scripts/remote.sh gpu

Exit Codes:
  0  成功; ready 返回 HTTP 200。
  1  ready 非 HTTP 200、GPU 概览为空, 或远端 checkout 内的 local.sh 正常执行但业务状态未就绪。
  2  参数、用法、配置或前置条件错误。
  4  入口自身发起运行后的外部依赖、网络、快照格式化或文件产物失败。
  其他非 0 由 ssh、rsync 或远端脚本透传。
EOF
}

usage_sync() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh sync --yes [options]

必需参数:
  --yes                  确认执行写操作。

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  --local-dir DIR        本地 checkout, 默认当前仓库根目录。
  --follow-links         rsync 跟随符号链接。
  --delete               删除远端多余的非排除文件。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

常用示例:
  # 前提: .env 已包含 REMOTE_HOST 和 REMOTE_DIR
  ./scripts/remote.sh sync --yes
EOF
}

usage_bootstrap() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh bootstrap --yes [options]

必需参数:
  --yes                  确认执行写操作。

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  --uv-index-url URL     为远端 local.sh bootstrap 注入 UV_INDEX_URL。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

远端动作:
  cd REMOTE_DIR && ./scripts/local.sh bootstrap

常用示例:
  # 前提: .env 已包含 REMOTE_HOST 和 REMOTE_DIR
  ./scripts/remote.sh bootstrap --yes
EOF
}

usage_lifecycle() {
  local action="${1:-${cmd:-start}}"
  cat <<EOF
用法:
  ./scripts/remote.sh ${action} --yes [options]

必需参数:
  --yes                  确认执行写操作。

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

远端动作:
  cd REMOTE_DIR && ./scripts/local.sh ${action}
EOF
}

usage_status() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh status [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

远端动作:
  cd REMOTE_DIR && ./scripts/local.sh status
EOF
}

usage_logs() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh logs [--tail N|all] [--follow] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  --tail N|all           输出日志尾部行数或全部日志; 默认 REMOTE_LOG_TAIL, 回退 200。
  --follow               跟随远端 local.sh logs。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST、REMOTE_DIR 和 REMOTE_LOG_TAIL; 已导出环境变量优先。
EOF
}

usage_ready() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh ready [--url URL] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --url URL              远端本机可访问的 ComfyUI base URL。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_READY_URL; 已导出环境变量优先。

远端动作:
  curl URL/system_stats
EOF
}

usage_tunnel() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh tunnel [--local-port PORT] [--remote-host HOST] [--remote-port PORT] [--dry-run] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --local-port PORT      覆盖 REMOTE_TUNNEL_LOCAL_PORT。
  --remote-host HOST     覆盖 REMOTE_TUNNEL_REMOTE_HOST。
  --remote-port PORT     覆盖 REMOTE_TUNNEL_REMOTE_PORT。
  --dry-run              只打印 ssh -L 命令, 不建立隧道。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_TUNNEL_*; 已导出环境变量优先。
EOF
}

usage_gpu() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh gpu [--connect-timeout SECONDS] [--json] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --connect-timeout N    SSH ConnectTimeout 秒数; 默认 REMOTE_GPU_CONNECT_TIMEOUT, 回退 10。
  --json                 stdout 只输出单个 JSON 文档。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_GPU_CONNECT_TIMEOUT; 已导出环境变量优先。
EOF
}

validate_remote_host() {
  local value="$1"
  [[ "$value" == *@* ]] || usage_error "--host must use USER@HOST" usage
  [[ "$value" != -* && "$value" != *[[:space:]]* ]] || usage_error "--host contains invalid characters: $value" usage
}

validate_remote_dir() {
  local value="$1"
  [[ "$value" == /* ]] || usage_error "--dir must be an absolute path" usage
  [[ "$value" =~ ^/[A-Za-z0-9._/+:-]*[A-Za-z0-9._/+:-]$ ]] || usage_error "--dir contains invalid characters: $value" usage
  [[ "$value" != *:* ]] || usage_error "--dir must not contain colon characters" usage
  [[ "$value" != *"/../"* && "$value" != */.. && "$value" != *"/./"* && "$value" != */. ]] || usage_error "--dir must not contain . or .. path segments" usage
}

validate_simple_host() {
  local label="$1"
  local value="$2"
  [[ "$value" != -* && "$value" != *[[:space:]]* ]] || usage_error "$label contains invalid characters: $value" usage
}

validate_port() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 && "$value" -le 65535 ]] || usage_error "$label must be a port between 1 and 65535" usage
}

validate_tail() {
  local value="$1"
  [[ "$value" == "all" || "$value" =~ ^[0-9]+$ ]] || usage_error "--tail must be a non-negative integer or all" usage
}

validate_positive_uint() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 ]] || usage_error "$label must be a positive integer" usage
}

validate_profile_arg() {
  local value="$1"
  [[ "$value" != -* && "$value" != *[[:space:]]* ]] || usage_error "--profile contains invalid characters: $value" usage
  [[ "$value" =~ ^[A-Za-z0-9._/+:-]+$ ]] || usage_error "--profile contains invalid characters: $value" usage
  [[ "$value" != *:* ]] || usage_error "--profile must not contain colon characters" usage
  [[ "$value" != *"/../"* && "$value" != ../* && "$value" != */.. && "$value" != ".." ]] || usage_error "--profile must not contain .. path segments" usage
}

validate_url() {
  local value="$1"
  [[ "$value" =~ ^https?://[^[:space:]]+$ ]] || usage_error "--url must be an http(s) URL without whitespace" usage
}

quote_cmd() {
  local out=""
  local part
  for part in "$@"; do
    if [[ -n "$out" ]]; then
      out+=" "
    fi
    out+="$(printf '%q' "$part")"
  done
  printf '%s\n' "$out"
}

remote_cd_cmd() {
  local dir="$1"
  shift
  printf 'cd %q && %s\n' "$dir" "$(quote_cmd "$@")"
}

remote_ready_cmd() {
  local endpoint="${1%/}/system_stats"
  # shellcheck disable=SC2016
  printf 'command -v curl >/dev/null 2>&1 || { printf "ERROR: missing required command: curl\\n" >&2; exit 2; }; code=$(curl --connect-timeout 2 --max-time 5 -sS -o /dev/null -w "%%{http_code}" %q); curl_status=$?; if [ "$curl_status" -ne 0 ]; then case "$curl_status" in 7|28|52) printf "000\\n"; exit 1 ;; *) printf "ERROR: curl failed with exit %%s\\n" "$curl_status" >&2; exit 4 ;; esac; fi; printf "%%s\\n" "$code"; [ "$code" = 200 ]\n' "$endpoint"
}

remote_gpu_snapshot_cmd() {
  printf '%s' "command -v nvidia-smi >/dev/null 2>&1 || { printf 'ERROR: missing required command: nvidia-smi\n' >&2; exit 2; }; printf '%s\n' __REMOTE_GPU_SUMMARY__; nvidia-smi --query-gpu=index,uuid,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,power.limit,compute_mode,driver_version --format=csv,noheader,nounits; printf '%s\n' __REMOTE_GPU_PROCESSES__; nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits"
}

require_yes() {
  local confirmed="$1"
  [[ "$confirmed" == true ]] || usage_error "remote write/lifecycle command requires --yes" usage
}

remote_config_error() {
  local missing="$1"
  local needs_dir="$2"
  local verb="is"
  if [[ "$missing" == *,* ]]; then
    verb="are"
  fi

  {
    printf 'ERROR: %s %s not configured.\n\n' "$missing" "$verb"
    printf 'remote.sh does not guess remote targets. Configure real values through exported environment, --profile FILE, or %s.\n\n' "$CONFIG_FILE"
    printf 'Add to config:\n'
    printf '  REMOTE_HOST=wangqiao@47.94.108.140\n'
    if [[ "$needs_dir" == true ]]; then
      printf '  REMOTE_DIR=/data/wangqiao/comfy-shell\n'
    else
      printf '  # REMOTE_DIR=/data/wangqiao/comfy-shell  # needed by checkout commands\n'
    fi
    printf '\nThen rerun the same command.\n'
    printf '\nOne-off override examples:\n'
    if [[ "$needs_dir" == true ]]; then
      printf '  ./scripts/remote.sh status --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell\n'
    else
      printf '  ./scripts/remote.sh tunnel --host wangqiao@47.94.108.140\n'
    fi
  } >&2
  exit 2
}

apply_remote_host_default() {
  if [[ -z "${host:-}" ]]; then
    host="$(config_value REMOTE_HOST)"
  fi
}

apply_remote_dir_default() {
  if [[ -z "${remote_dir:-}" ]]; then
    remote_dir="$(config_value REMOTE_DIR)"
  fi
}

require_host() {
  apply_remote_host_default
  [[ -n "$host" ]] || remote_config_error "REMOTE_HOST" false
  validate_remote_host "$host"
}

require_host_dir() {
  local missing=""
  apply_remote_host_default
  apply_remote_dir_default
  if [[ -z "$host" ]]; then
    missing="REMOTE_HOST"
  fi
  if [[ -z "$remote_dir" ]]; then
    missing="${missing:+$missing, }REMOTE_DIR"
  fi
  [[ -z "$missing" ]] || remote_config_error "$missing" true
  validate_remote_host "$host"
  validate_remote_dir "$remote_dir"
}

print_remote_plan() {
  local action="$1"
  local host_value="$2"
  local dir_value="$3"
  local config_value="$4"
  local delete_value="$5"
  shift 5
  local remote_action

  section "Remote Plan"
  event "ACTION" "$action"
  event "HOST" "$host_value"
  if [[ -n "$dir_value" ]]; then
    event "DIR" "$dir_value"
  fi
  if [[ -n "$config_value" ]]; then
    event "CONFIG" "$config_value"
  fi
  if [[ -n "$delete_value" ]]; then
    event "DELETE" "$delete_value"
  fi
  for remote_action in "$@"; do
    event "REMOTE" "$remote_action"
  done
}

parse_host_common() {
  consumed=0
  case "$1" in
    --profile)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--profile requires a value" usage
      validate_profile_arg "$2"
      profile="$2"
      set_config_file "$2"
      require_config_file
      consumed=2
      return 0
      ;;
    --host)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
      host="$2"
      consumed=2
      return 0
      ;;
  esac
  return 1
}

parse_host_dir_common() {
  if parse_host_common "$@"; then
    return 0
  fi
  consumed=0
  case "$1" in
    --dir)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--dir requires a value" usage
      remote_dir="$2"
      consumed=2
      return 0
      ;;
  esac
  return 1
}

cmd="${1:-}"
case "$cmd" in
  -h|--help|"")
    usage
    [[ -n "$cmd" ]] && exit 0 || exit 2
    ;;
esac
shift

case "$cmd" in
  sync)
    host=""
    remote_dir=""
    profile=""
    local_dir="$ROOT_DIR"
    follow_links=false
    delete_remote=false
    yes=false
    while [[ $# -gt 0 ]]; do
      if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
      case "$1" in
        --local-dir)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--local-dir requires a value" usage
          local_dir="$2"
          shift 2
          ;;
        --follow-links)
          follow_links=true
          shift
          ;;
        --delete)
          delete_remote=true
          shift
          ;;
        --yes)
          yes=true
          shift
          ;;
        -h|--help)
          usage_sync
          exit 0
          ;;
        *)
          usage_error "unknown sync option: $1" usage_sync
          ;;
      esac
    done
    require_host_dir
    require_yes "$yes"
    require_cmd ssh
    require_cmd rsync
    local_dir="$(abs_path "$local_dir")"
    [[ -d "$local_dir" ]] || die "local dir not found: $local_dir" 2

    print_remote_plan \
      "sync" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "$delete_remote" \
      "ssh mkdir -p $remote_dir" \
      "rsync $local_dir/ -> ${host}:${remote_dir%/}/"
    ssh_mkdir_args=(ssh -o ConnectTimeout=10 "$host" "mkdir -p $(printf '%q' "$remote_dir")")
    "${ssh_mkdir_args[@]}"
    rsync_args=(-avh --progress --rsh "ssh -o ConnectTimeout=10")
    if [[ "$follow_links" == true ]]; then
      rsync_args+=(-L)
    fi
    if [[ "$delete_remote" == true ]]; then
      rsync_args+=(--delete)
    fi
    rsync_args+=(
      --exclude ".git/"
      --exclude ".env"
      --exclude ".venv/"
      --exclude ".run/"
      --exclude "logs/"
      --exclude "__pycache__/"
      --exclude ".DS_Store"
      --exclude "ComfyUI/models/"
      --exclude "ComfyUI/output/"
      --exclude "ComfyUI/input/"
      --exclude "ComfyUI/temp/"
      --exclude "ComfyUI/user/"
      "${local_dir%/}/"
      "${host}:${remote_dir%/}/"
    )
    print_command rsync "${rsync_args[@]}"
    exec rsync "${rsync_args[@]}"
    ;;
  bootstrap)
    host=""
    remote_dir=""
    profile=""
    uv_index_url=""
    yes=false
    while [[ $# -gt 0 ]]; do
      if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
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
          usage_bootstrap
          exit 0
          ;;
        *)
          usage_error "unknown bootstrap option: $1" usage_bootstrap
          ;;
      esac
    done
    require_host_dir
    require_yes "$yes"
    if [[ -n "$uv_index_url" ]]; then
      validate_url "$uv_index_url"
    fi
    require_cmd ssh
    bootstrap_args=(./scripts/local.sh bootstrap)
    bootstrap_remote_action="cd $remote_dir && $(quote_cmd "${bootstrap_args[@]}")"
    if [[ -n "$uv_index_url" ]]; then
      bootstrap_remote_action="cd $remote_dir && UV_INDEX_URL=$uv_index_url $(quote_cmd "${bootstrap_args[@]}")"
    fi
    print_remote_plan \
      "bootstrap" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "" \
      "$bootstrap_remote_action"
    if [[ -n "$uv_index_url" ]]; then
      remote_command="$(remote_cd_cmd "$remote_dir" env "UV_INDEX_URL=$uv_index_url" "${bootstrap_args[@]}")"
      ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
      exec "${ssh_args[@]}"
    fi
    remote_command="$(remote_cd_cmd "$remote_dir" "${bootstrap_args[@]}")"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
    ;;
  start|stop|restart)
    host=""
    remote_dir=""
    profile=""
    yes=false
    while [[ $# -gt 0 ]]; do
      if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
      case "$1" in
        --yes)
          yes=true
          shift
          ;;
        -h|--help)
          usage_lifecycle "$cmd"
          exit 0
          ;;
        *)
          usage_error "unknown ${cmd} option: $1" usage_lifecycle "$cmd"
          ;;
      esac
    done
    require_host_dir
    require_yes "$yes"
    require_cmd ssh
    lifecycle_args=(./scripts/local.sh "$cmd")
    print_remote_plan \
      "$cmd" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "" \
      "cd $remote_dir && $(quote_cmd "${lifecycle_args[@]}")"
    remote_command="$(remote_cd_cmd "$remote_dir" "${lifecycle_args[@]}")"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
    ;;
  status)
    host=""
    remote_dir=""
    profile=""
    while [[ $# -gt 0 ]]; do
      if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
      case "$1" in
        -h|--help)
          usage_status
          exit 0
          ;;
        *)
          usage_error "unknown status option: $1" usage_status
          ;;
      esac
    done
    require_host_dir
    require_cmd ssh
    status_args=(./scripts/local.sh status)
    remote_command="$(remote_cd_cmd "$remote_dir" "${status_args[@]}")"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
    ;;
  ready)
    host=""
    remote_dir=""
    profile=""
    url=""
    while [[ $# -gt 0 ]]; do
      if parse_host_common "$@"; then shift "$consumed"; continue; fi
      case "$1" in
        --url)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--url requires a value" usage
          url="$2"
          shift 2
          ;;
        -h|--help)
          usage_ready
          exit 0
          ;;
        *)
          usage_error "unknown ready option: $1" usage_ready
          ;;
      esac
    done
    url="${url:-$(config_value REMOTE_READY_URL)}"
    url="${url:-$DEFAULT_READY_URL}"
    require_host
    validate_url "$url"
    require_cmd ssh
    remote_command="$(remote_ready_cmd "$url")"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
    ;;
  logs)
    host=""
    remote_dir=""
    profile=""
    tail_lines=""
    follow=false
    while [[ $# -gt 0 ]]; do
      if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
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
          usage_logs
          exit 0
          ;;
        *)
          usage_error "unknown logs option: $1" usage_logs
          ;;
      esac
    done
    tail_lines="${tail_lines:-$(config_value REMOTE_LOG_TAIL)}"
    tail_lines="${tail_lines:-$DEFAULT_LOG_TAIL}"
    require_host_dir
    validate_tail "$tail_lines"
    require_cmd ssh
    if [[ "$follow" == true ]]; then
      remote_command="$(remote_cd_cmd "$remote_dir" ./scripts/local.sh logs)"
      ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
      exec "${ssh_args[@]}"
    fi
    if [[ "$tail_lines" == "all" ]]; then
      remote_command="$(remote_cd_cmd "$remote_dir" cat logs/comfyui.log)"
      ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
      exec "${ssh_args[@]}"
    fi
    remote_command="$(remote_cd_cmd "$remote_dir" tail -n "$tail_lines" logs/comfyui.log)"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
    ;;
  tunnel)
    host=""
    remote_dir=""
    profile=""
    local_port=""
    remote_host=""
    remote_port=""
    dry_run=false
    while [[ $# -gt 0 ]]; do
      if parse_host_common "$@"; then shift "$consumed"; continue; fi
      case "$1" in
        --local-port)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--local-port requires a value" usage
          local_port="$2"
          shift 2
          ;;
        --remote-host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--remote-host requires a value" usage
          remote_host="$2"
          shift 2
          ;;
        --remote-port)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--remote-port requires a value" usage
          remote_port="$2"
          shift 2
          ;;
        --dry-run)
          dry_run=true
          shift
          ;;
        -h|--help)
          usage_tunnel
          exit 0
          ;;
        *)
          usage_error "unknown tunnel option: $1" usage_tunnel
          ;;
      esac
    done
    local_port="${local_port:-$(config_value REMOTE_TUNNEL_LOCAL_PORT)}"
    local_port="${local_port:-$DEFAULT_LOCAL_PORT}"
    remote_host="${remote_host:-$(config_value REMOTE_TUNNEL_REMOTE_HOST)}"
    remote_host="${remote_host:-$DEFAULT_REMOTE_HOST}"
    remote_port="${remote_port:-$(config_value REMOTE_TUNNEL_REMOTE_PORT)}"
    remote_port="${remote_port:-$DEFAULT_REMOTE_PORT}"
    require_host
    validate_port "--local-port" "$local_port"
    validate_port "--remote-port" "$remote_port"
    validate_simple_host "--remote-host" "$remote_host"
    require_cmd ssh
    ssh_args=(ssh -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -N -L "${local_port}:${remote_host}:${remote_port}" "$host")
    print_command "${ssh_args[@]}"
    if [[ "$dry_run" == true ]]; then
      exit 0
    fi
    exec "${ssh_args[@]}"
    ;;
  gpu)
    host=""
    remote_dir=""
    profile=""
    connect_timeout=""
    json_output=false
    while [[ $# -gt 0 ]]; do
      if parse_host_common "$@"; then shift "$consumed"; continue; fi
      case "$1" in
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
          usage_gpu
          exit 0
          ;;
        *)
          usage_error "unknown gpu option: $1" usage_gpu
          ;;
      esac
    done
    connect_timeout="${connect_timeout:-$(config_value REMOTE_GPU_CONNECT_TIMEOUT)}"
    connect_timeout="${connect_timeout:-$DEFAULT_CONNECT_TIMEOUT}"
    require_host
    validate_positive_uint "--connect-timeout" "$connect_timeout"
    require_cmd ssh
    require_cmd python3
    formatter_args=("$ROOT_DIR/scripts/lib/remote_gpu_format.py" --host "$host")
    if [[ "$json_output" == true ]]; then
      formatter_args+=(--json)
    fi
    ssh_args=(ssh -o ConnectTimeout="$connect_timeout" "$host" "$(remote_gpu_snapshot_cmd)")
    set +e
    snapshot="$("${ssh_args[@]}")"
    ssh_status=$?
    set -e
    if [[ "$ssh_status" -ne 0 ]]; then
      exit "$ssh_status"
    fi
    printf '%s\n' "$snapshot" | python3 "${formatter_args[@]}"
    ;;
  *)
    usage_error "unknown command: $cmd" usage
    ;;
esac
