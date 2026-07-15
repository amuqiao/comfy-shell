#!/usr/bin/env bash
# remote.sh - reusable SSH orchestration for a remote project checkout

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DEFAULT_PROFILE="server-cuda-a10"
DEFAULT_READY_URL="http://127.0.0.1:8188"
DEFAULT_LOCAL_PORT="8188"
DEFAULT_REMOTE_HOST="127.0.0.1"
DEFAULT_REMOTE_PORT="8188"
DEFAULT_LOG_TAIL="200"

usage() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh sync --host USER@HOST --dir REMOTE_DIR --yes [--local-dir DIR] [--follow-links] [--delete]
  ./scripts/remote.sh bootstrap --host USER@HOST --dir REMOTE_DIR --yes [--profile NAME] [--uv-index-url URL]
  ./scripts/remote.sh start --host USER@HOST --dir REMOTE_DIR --yes
  ./scripts/remote.sh stop --host USER@HOST --dir REMOTE_DIR --yes
  ./scripts/remote.sh restart --host USER@HOST --dir REMOTE_DIR --yes
  ./scripts/remote.sh status --host USER@HOST --dir REMOTE_DIR
  ./scripts/remote.sh ready --host USER@HOST [--url URL]
  ./scripts/remote.sh logs --host USER@HOST --dir REMOTE_DIR [--tail N|all] [--follow]
  ./scripts/remote.sh tunnel --host USER@HOST [--local-port PORT] [--remote-host HOST] [--remote-port PORT] [--dry-run]
  ./scripts/remote.sh -h|--help

作用域:
  从本地遥控一份远端项目 checkout。当前项目中用于管理远端 comfy-shell:
  同步壳仓库、激活 profile、执行远端 dev.sh 生命周期、查看日志、健康检查和建立 SSH 隧道。

不负责:
  不管理 Docker、systemd、第三方 custom_nodes、模型自动下载或公网端口暴露。
  不读取远端 secret, 不执行自由 shell 片段。
  远端目录必须是绝对路径, 且只能包含字母、数字、点、下划线、斜杠、加号和连字符。

运行环境:
  Requires: Bash, ssh
  sync additionally requires: rsync
  Remote checkout requires: comfy-shell repository with scripts/dev.sh and scripts/env.sh

默认行为:
  bootstrap 默认远端执行 ./scripts/env.sh use server-cuda-a10 后再执行 ./scripts/dev.sh bootstrap。
  start/stop/restart/status 委托远端 ./scripts/dev.sh 对应子命令。
  ready 默认检查 http://127.0.0.1:8188/system_stats。
  logs 默认只输出远端 logs/comfyui.log 最后 200 行; --follow 才持续跟随。
  tunnel 默认映射 http://127.0.0.1:8188 -> 远端 127.0.0.1:8188。

配置与环境变量:
  本入口只读取显式 CLI 参数，不读取 .env。
  远端 .env 由 bootstrap 的 --profile 激活，或由用户在远端自行维护。
  --yes 是远端写入、上传、启动、停止和重启动作的显式确认参数。

输出:
  stdout: 将执行的命令、远端脚本输出、HTTP 状态码、日志内容或隧道映射。
  stderr: 参数错误、缺少依赖、ssh/rsync/curl/tail 诊断。

副作用与保护边界:
  sync --yes 会创建远端目录并上传本地 checkout; --delete 会删除远端多余的非排除文件。
  bootstrap 会在远端写 .env、.venv、.run/、logs/ 并访问 Python 包索引。
  start/stop/restart 会在远端启动或停止 ComfyUI 进程。
  tunnel 会占用本地端口并保持 SSH 前台进程。
  所有远端操作都必须显式传 --host; 需要远端项目目录的命令必须显式传 --dir。

常用示例:
  ./scripts/remote.sh sync --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --yes
  ./scripts/remote.sh bootstrap --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --profile server-cuda-a10 --yes
  ./scripts/remote.sh start --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --yes
  ./scripts/remote.sh status --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell
  ./scripts/remote.sh logs --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --tail 200
  ./scripts/remote.sh tunnel --host wangqiao@47.94.108.140

Exit Codes:
  0  成功; ready 返回 HTTP 200。
  1  ready 非 HTTP 200, 或远端 dev.sh 正常执行但业务状态未就绪。
  2  参数、用法、配置或前置条件错误。
  3  入口保护拒绝继续, 例如目标资源或运行模式冲突。
  4  入口自身发起运行后的外部依赖、网络或文件产物失败。
  其他非 0 由 ssh、rsync 或远端脚本透传。
EOF
}

validate_remote_host() {
  local value="$1"
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

validate_profile_name() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9_.-]+$ && "$value" != .* ]] || usage_error "--profile must be a simple profile name" usage
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

require_yes() {
  local confirmed="$1"
  [[ "$confirmed" == true ]] || usage_error "remote write/lifecycle command requires --yes" usage
}

parse_host_dir_args() {
  host=""
  remote_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
        host="$2"
        shift 2
        ;;
      --dir)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--dir requires a value" usage
        remote_dir="$2"
        shift 2
        ;;
      *)
        usage_error "unknown ${cmd} option: $1" usage
        ;;
    esac
  done
  [[ -n "$host" ]] || usage_error "--host is required" usage
  [[ -n "$remote_dir" ]] || usage_error "--dir is required" usage
  validate_remote_host "$host"
  validate_remote_dir "$remote_dir"
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
    local_dir="$ROOT_DIR"
    follow_links=false
    delete_remote=false
    yes=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
          host="$2"
          shift 2
          ;;
        --dir)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--dir requires a value" usage
          remote_dir="$2"
          shift 2
          ;;
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
          usage
          exit 0
          ;;
        *)
          usage_error "unknown sync option: $1" usage
          ;;
      esac
    done
    [[ -n "$host" ]] || usage_error "--host is required" usage
    [[ -n "$remote_dir" ]] || usage_error "--dir is required" usage
    validate_remote_host "$host"
    validate_remote_dir "$remote_dir"
    require_yes "$yes"
    require_cmd ssh
    require_cmd rsync
    local_dir="$(abs_path "$local_dir")"
    [[ -d "$local_dir" ]] || die "local dir not found: $local_dir" 2

    ssh -o ConnectTimeout=10 "$host" "mkdir -p $(printf '%q' "$remote_dir")"
    rsync_args=(-avh --progress)
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
    profile="$DEFAULT_PROFILE"
    uv_index_url=""
    yes=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
          host="$2"
          shift 2
          ;;
        --dir)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--dir requires a value" usage
          remote_dir="$2"
          shift 2
          ;;
        --profile)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--profile requires a value" usage
          profile="$2"
          shift 2
          ;;
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
    [[ -n "$host" ]] || usage_error "--host is required" usage
    [[ -n "$remote_dir" ]] || usage_error "--dir is required" usage
    validate_remote_host "$host"
    validate_remote_dir "$remote_dir"
    validate_profile_name "$profile"
    require_yes "$yes"
    if [[ -n "$uv_index_url" ]]; then
      validate_url "$uv_index_url"
    fi
    require_cmd ssh
    if [[ -n "$uv_index_url" ]]; then
      exec ssh -o ConnectTimeout=10 "$host" "$(remote_cd_cmd "$remote_dir" ./scripts/env.sh use "$profile") && $(remote_cd_cmd "$remote_dir" env "UV_INDEX_URL=$uv_index_url" ./scripts/dev.sh bootstrap)"
    fi
    exec ssh -o ConnectTimeout=10 "$host" "$(remote_cd_cmd "$remote_dir" ./scripts/env.sh use "$profile") && $(remote_cd_cmd "$remote_dir" ./scripts/dev.sh bootstrap)"
    ;;
  status)
    parse_host_dir_args "$@"
    require_cmd ssh
    exec ssh -o ConnectTimeout=10 "$host" "$(remote_cd_cmd "$remote_dir" ./scripts/dev.sh "$cmd")"
    ;;
  start|stop|restart)
    host=""
    remote_dir=""
    yes=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
          host="$2"
          shift 2
          ;;
        --dir)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--dir requires a value" usage
          remote_dir="$2"
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
          usage_error "unknown ${cmd} option: $1" usage
          ;;
      esac
    done
    [[ -n "$host" ]] || usage_error "--host is required" usage
    [[ -n "$remote_dir" ]] || usage_error "--dir is required" usage
    validate_remote_host "$host"
    validate_remote_dir "$remote_dir"
    require_yes "$yes"
    require_cmd ssh
    exec ssh -o ConnectTimeout=10 "$host" "$(remote_cd_cmd "$remote_dir" ./scripts/dev.sh "$cmd")"
    ;;
  ready)
    host=""
    url="$DEFAULT_READY_URL"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
          host="$2"
          shift 2
          ;;
        --url)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--url requires a value" usage
          url="$2"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown ready option: $1" usage
          ;;
      esac
    done
    [[ -n "$host" ]] || usage_error "--host is required" usage
    validate_remote_host "$host"
    validate_url "$url"
    require_cmd ssh
    exec ssh -o ConnectTimeout=10 "$host" "$(remote_ready_cmd "$url")"
    ;;
  logs)
    host=""
    remote_dir=""
    tail_lines="$DEFAULT_LOG_TAIL"
    follow=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
          host="$2"
          shift 2
          ;;
        --dir)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--dir requires a value" usage
          remote_dir="$2"
          shift 2
          ;;
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
    [[ -n "$host" ]] || usage_error "--host is required" usage
    [[ -n "$remote_dir" ]] || usage_error "--dir is required" usage
    validate_remote_host "$host"
    validate_remote_dir "$remote_dir"
    validate_tail "$tail_lines"
    require_cmd ssh
    if [[ "$follow" == true ]]; then
      exec ssh -o ConnectTimeout=10 "$host" "$(remote_cd_cmd "$remote_dir" ./scripts/dev.sh logs)"
    fi
    if [[ "$tail_lines" == "all" ]]; then
      exec ssh -o ConnectTimeout=10 "$host" "$(remote_cd_cmd "$remote_dir" cat logs/comfyui.log)"
    fi
    exec ssh -o ConnectTimeout=10 "$host" "$(remote_cd_cmd "$remote_dir" tail -n "$tail_lines" logs/comfyui.log)"
    ;;
  tunnel)
    host=""
    local_port="$DEFAULT_LOCAL_PORT"
    remote_host="$DEFAULT_REMOTE_HOST"
    remote_port="$DEFAULT_REMOTE_PORT"
    dry_run=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
          host="$2"
          shift 2
          ;;
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
          usage
          exit 0
          ;;
        *)
          usage_error "unknown tunnel option: $1" usage
          ;;
      esac
    done
    [[ -n "$host" ]] || usage_error "--host is required" usage
    validate_remote_host "$host"
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
  *)
    usage_error "unknown command: $cmd" usage
    ;;
esac
