#!/usr/bin/env bash
# tunnel.sh - SSH local port forwarding for remote ComfyUI

set -euo pipefail

DEFAULT_SERVER_USER="wangqiao"
DEFAULT_SERVER_HOST="47.94.108.140"
DEFAULT_LOCAL_PORT="8188"
DEFAULT_REMOTE_HOST="127.0.0.1"
DEFAULT_REMOTE_PORT="8188"

usage() {
  cat <<'EOF'
用法:
  ./scripts/tunnel.sh [options]
  ./scripts/tunnel.sh -h|--help

作用域:
  在当前机器上打开 SSH 本地端口转发, 用浏览器访问远程服务器上的 ComfyUI。
  默认映射:
    http://127.0.0.1:8188 -> wangqiao@47.94.108.140:127.0.0.1:8188

运行环境:
  Requires: Bash, ssh
  Run from: 你的 Mac 或其他本地电脑
  Server side: 远程服务器已执行 ./scripts/dev.sh start, 且 ComfyUI 监听 127.0.0.1:8188

不负责:
  不登录后执行远程命令,不启动服务器 ComfyUI,不安装依赖,不下载模型,
  不修改 .env,不打开浏览器,不暴露公网端口。

选项:
  --server HOST       远程服务器 IP 或域名, 默认 47.94.108.140
  --user USER         SSH 用户, 默认 wangqiao
  --local-port PORT   本地监听端口, 默认 8188
  --remote-host HOST  远程 ComfyUI 监听地址, 默认 127.0.0.1
  --remote-port PORT  远程 ComfyUI 端口, 默认 8188
  -h, --help          显示帮助

环境变量:
  SERVER_HOST         等价于 --server
  SERVER_USER         等价于 --user
  LOCAL_PORT          等价于 --local-port
  REMOTE_HOST         等价于 --remote-host
  REMOTE_PORT         等价于 --remote-port

输出:
  stdout 显示映射关系和浏览器访问地址。
  stderr 显示参数错误或 ssh 错误。

副作用:
  当前终端会被 ssh 隧道占用。保持窗口打开即可访问; 按 Ctrl+C 关闭隧道。
  不写入项目文件。

常用示例:
  ./scripts/tunnel.sh
  ./scripts/tunnel.sh --local-port 18188
  SERVER_HOST=47.94.108.140 ./scripts/tunnel.sh

Exit Codes:
  0  隧道正常退出
  2  参数错误或 ssh 缺失
  ssh 原始退出码表示连接失败、认证失败或网络中断
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

is_port() {
  local value="$1"
  case "$value" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [[ "$value" -ge 1 && "$value" -le 65535 ]]
}

require_non_empty() {
  local label="$1"
  local value="$2"
  [[ -n "$value" ]] || die "$label must not be empty" 2
}

server_user="${SERVER_USER:-$DEFAULT_SERVER_USER}"
server_host="${SERVER_HOST:-$DEFAULT_SERVER_HOST}"
local_port="${LOCAL_PORT:-$DEFAULT_LOCAL_PORT}"
remote_host="${REMOTE_HOST:-$DEFAULT_REMOTE_HOST}"
remote_port="${REMOTE_PORT:-$DEFAULT_REMOTE_PORT}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --server)
      [[ "$#" -ge 2 ]] || die "--server requires HOST" 2
      server_host="$2"
      shift 2
      ;;
    --user)
      [[ "$#" -ge 2 ]] || die "--user requires USER" 2
      server_user="$2"
      shift 2
      ;;
    --local-port)
      [[ "$#" -ge 2 ]] || die "--local-port requires PORT" 2
      local_port="$2"
      shift 2
      ;;
    --remote-host)
      [[ "$#" -ge 2 ]] || die "--remote-host requires HOST" 2
      remote_host="$2"
      shift 2
      ;;
    --remote-port)
      [[ "$#" -ge 2 ]] || die "--remote-port requires PORT" 2
      remote_port="$2"
      shift 2
      ;;
    *)
      die "unknown option: $1" 2
      ;;
  esac
done

command -v ssh >/dev/null 2>&1 || die "ssh not found" 2

require_non_empty "server user" "$server_user"
require_non_empty "server host" "$server_host"
require_non_empty "remote host" "$remote_host"
is_port "$local_port" || die "local port must be 1-65535, got: $local_port" 2
is_port "$remote_port" || die "remote port must be 1-65535, got: $remote_port" 2

printf 'Opening ComfyUI tunnel:\n'
printf '  local:  http://127.0.0.1:%s\n' "$local_port"
printf '  remote: %s@%s:%s:%s\n' "$server_user" "$server_host" "$remote_host" "$remote_port"
printf '\n'
printf 'Keep this terminal open. Press Ctrl+C to close the tunnel.\n'
printf '\n'

exec ssh -N -L "${local_port}:${remote_host}:${remote_port}" "${server_user}@${server_host}"
