#!/usr/bin/env bash
# local.sh - local ComfyUI lifecycle for comfy-shell

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

COMFY_DIR="$ROOT_DIR/ComfyUI"
RUN_DIR="$ROOT_DIR/.run"
LOG_DIR="$ROOT_DIR/logs"
PID_FILE="$RUN_DIR/comfyui.pid"
LOCK_DIR="$RUN_DIR/comfyui.lock"
LOG_FILE="$LOG_DIR/comfyui.log"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
UV_BIN="${UV_BIN:-uv}"
LOCK_HELD=0

usage() {
  cat <<'EOF'
用法:
  ./scripts/local.sh <command> [--profile FILE]
  ./scripts/local.sh logs
  ./scripts/local.sh -h|--help

作用域:
  管理当前机器上的 ComfyUI 运行。负责创建项目 .venv、安装 ComfyUI / Manager
  依赖、后台启动 ComfyUI、停止进程、查看状态和日志。
  不负责模型下载、第三方 custom_nodes、Docker、服务器 systemd 或远程部署。

运行环境:
  Requires: Bash, uv, curl
  Recommended: lsof
  Note: stale PID / port-owner recovery requires lsof.
  Python: 由 uv 按配置中的 COMFY_PYTHON 创建到仓库根目录 .venv。

命令:
  bootstrap     使用 uv 创建 .venv, 安装 ComfyUI 和 ComfyUI-Manager 依赖
  start         后台启动 ComfyUI, 默认启用 Manager
  stop          停止后台 ComfyUI
  restart       重启 ComfyUI
  status        查看 PID、日志、URL 和 /system_stats
  logs          跟随查看 logs/comfyui.log
  help          显示本帮助

配置:
  bootstrap/start/stop/restart/status 默认读取仓库根目录 .env。
  如需读取其他配置文件, 必须显式传 --profile FILE。
  logs 只读取 logs/comfyui.log, 不需要 profile。
  进程环境变量优先于配置文件值。
  COMFY_HOST          本机阶段只允许 127.0.0.1 / localhost / ::1
  COMFY_PORT          ComfyUI 监听端口
  COMFY_PYTHON        uv 创建 .venv 使用的 Python 版本
  TORCH_PRE           true 时 PyTorch 安装传 --pre
  TORCH_INDEX_URL     只用于 torch / torchvision / torchaudio 安装
  UV_INDEX_URL        uv 自身读取的默认包索引, 可临时设为国内 PyPI 镜像
  HF_ENDPOINT         透传给 ComfyUI 进程, 供后续模型下载/节点使用

输出:
  stdout: 阶段、PID、URL、日志路径、健康检查结果。
  stderr: 缺少配置、依赖安装失败、Manager 不可导入、端口占用或启动失败详情。

默认行为:
  bootstrap 只准备 Python 环境和依赖, 不下载模型, 不启动服务。
  start 只从已有 .venv 启动 ComfyUI, 自动传 --enable-manager。
  status/logs/stop 不修改 Python 环境。
  本脚本不会在 start 中执行 pip 安装、模型下载或第三方 custom_nodes 安装。
  启用 Manager 后, 上游 ComfyUI-Manager 可能执行自己的安全检查或处理此前
  从 UI 排队的安装任务。

成功标准:
  bootstrap 成功等于 .venv 可用、torch 可 import、Manager requirements 安装完成。
  start 成功等于后台 PID 存活且 http://COMFY_HOST:COMFY_PORT/system_stats 可访问。
  status 成功等于完成只读探测; system_stats 不可达会在输出中显示 DOWN。

运行产物:
  .venv/               Python 虚拟环境
  .run/                运行时状态目录
  .run/comfyui.pid     后台 ComfyUI PID
  .run/comfyui.lock    start/stop/restart 生命周期锁
  logs/                日志目录
  logs/comfyui.log     ComfyUI stdout/stderr 日志

副作用与保护边界:
  bootstrap 会写入 .venv、.run/、logs/ 并访问 Python 包索引。
  start 会写入 .run/comfyui.pid 和 logs/comfyui.log, 并只监听本机 loopback。
  stop 优先停止 pid 文件指向且命令行匹配 ComfyUI 的进程; pid 文件缺失或
  陈旧时, 会通过 lsof 恢复并停止匹配当前 host/port 的 ComfyUI port owner。
  start 不会执行脚本级依赖安装; Manager 不可导入时直接失败。

常用示例:
  UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple ./scripts/local.sh bootstrap
  ./scripts/local.sh bootstrap --profile .env.example
  ./scripts/local.sh start
  ./scripts/local.sh status
  ./scripts/local.sh logs
  ./scripts/local.sh stop

Exit Codes:
  0  成功
  1  安装、启动、健康检查或 Manager 校验失败
  2  缺少 command、非法参数、配置文件缺失或依赖缺失
  4  端口占用、pid 文件异常或进程停止保护失败
EOF
}

command_usage() {
  local name="$1"
  case "$name" in
    bootstrap)
      cat <<'EOF'
用法:
  ./scripts/local.sh bootstrap [--profile FILE]
  ./scripts/local.sh bootstrap -h|--help

作用域:
  使用 uv 创建或复用仓库根目录 .venv, 安装 PyTorch、ComfyUI requirements
  和 ComfyUI-Manager requirements。

配置与环境变量:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  进程环境变量优先于配置文件值。
  TORCH_PRE=true 时, PyTorch 安装传 --pre。
  TORCH_INDEX_URL 只影响 torch / torchvision / torchaudio。
  UV_INDEX_URL 可在命令前临时设置, 影响 ComfyUI requirements 和 Manager
  requirements 等普通 PyPI 依赖。

PyTorch wheel 源示例:
  macos-mps config example:
    TORCH_PRE=true
    TORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cpu

  server-cuda-a10 config example:
    TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124

成功标准:
  .venv 可用。
  torch 可 import。
  comfyui_manager 可 import。

副作用:
  会访问网络并写入 .venv、.run/、logs/。不会下载模型,不会启动 ComfyUI。

常用示例:
  ./scripts/local.sh bootstrap --profile .env.example
  ./scripts/local.sh bootstrap
  UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple ./scripts/local.sh bootstrap
EOF
      ;;
    start)
      cat <<'EOF'
用法:
  ./scripts/local.sh start [--profile FILE]
  ./scripts/local.sh start -h|--help

作用域:
  后台启动本机 ComfyUI, 自动传 --enable-manager, 并轮询 /system_stats。

前置条件:
  .env 存在, 或已显式传入 --profile FILE。
  .venv 已创建。
  comfyui_manager 可 import；否则先执行 ./scripts/nodes.sh install manager。

副作用:
  写入 .run/comfyui.pid 和 logs/comfyui.log。
  本脚本不会执行 pip 安装、模型下载或第三方 custom_nodes 安装。
  启用 Manager 后, 上游 ComfyUI-Manager 可能执行自己的安全检查或处理此前
  从 UI 排队的安装任务。

成功标准:
  输出 READY comfyui http://COMFY_HOST:COMFY_PORT。
  浏览器可打开同一个 URL。

常用示例:
  ./scripts/local.sh start
  ./scripts/local.sh start --profile .env.example
  ./scripts/local.sh status
EOF
      ;;
    stop)
      cat <<'EOF'
用法:
  ./scripts/local.sh stop [--profile FILE]
  ./scripts/local.sh stop -h|--help

作用域:
  停止由本脚本启动的本机 ComfyUI 进程。

保护边界:
  只停止 pid 文件指向且命令行匹配 ComfyUI 的进程。
  如果 pid 文件陈旧、缺失或指向非 ComfyUI 进程,会通过 lsof 查找当前端口。
  只有 port owner 命令行匹配当前 .venv、host、port 和 --enable-manager 时才停止。

常用示例:
  ./scripts/local.sh stop
  ./scripts/local.sh stop --profile .env.example
EOF
      ;;
    restart)
      cat <<'EOF'
用法:
  ./scripts/local.sh restart [--profile FILE]
  ./scripts/local.sh restart -h|--help

作用域:
  先 stop 再 start 本机 ComfyUI。

常用示例:
  ./scripts/local.sh restart
  ./scripts/local.sh restart --profile .env.example
EOF
      ;;
    status)
      cat <<'EOF'
用法:
  ./scripts/local.sh status [--profile FILE]
  ./scripts/local.sh status -h|--help

作用域:
  只读查看本机 ComfyUI PID、URL、日志路径和 /system_stats 可达性。

常用示例:
  ./scripts/local.sh status
  ./scripts/local.sh status --profile .env.example
EOF
      ;;
    logs)
      cat <<'EOF'
用法:
  ./scripts/local.sh logs
  ./scripts/local.sh logs -h|--help

作用域:
  跟随查看 logs/comfyui.log。

常用示例:
  ./scripts/local.sh logs
EOF
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

release_lifecycle_lock() {
  if [[ "$LOCK_HELD" -eq 1 ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

acquire_lifecycle_lock() {
  mkdir -p "$RUN_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
    trap release_lifecycle_lock EXIT INT TERM
  else
    die "lifecycle lock exists: $LOCK_DIR; another start/stop/restart may be running" 4
  fi
}

parse_config_args() {
  local command_name="$1"
  shift
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ "$#" -ge 2 ]] || die "--profile requires a file" 2
        set_config_file "$2"
        shift 2
        ;;
      --profile=*)
        set_config_file "${1#--profile=}"
        shift
        ;;
      *)
        die "$command_name takes only optional --profile FILE" 2
        ;;
    esac
  done
  require_config_file
}

load_config() {
  require_config_file
  # shellcheck disable=SC2034
  set_required_config_value COMFY_PROFILE COMFY_PROFILE
  set_required_config_value COMFY_ENV_BACKEND COMFY_ENV_BACKEND
  set_required_config_value COMFY_PYTHON_VERSION COMFY_PYTHON
  # shellcheck disable=SC2034
  set_required_config_value COMFY_DEVICE COMFY_DEVICE
  set_required_config_value COMFY_HOST COMFY_HOST
  set_required_config_value COMFY_PORT COMFY_PORT
  set_required_config_value COMFY_MODEL_ROOT_VALUE COMFY_MODEL_ROOT
  set_required_config_value COMFY_OUTPUT_ROOT COMFY_OUTPUT_ROOT
  TORCH_PRE_VALUE="$(config_value TORCH_PRE)"
  TORCH_INDEX_URL_VALUE="$(config_value TORCH_INDEX_URL)"
  HF_ENDPOINT_VALUE="$(config_value HF_ENDPOINT)"
  CUDA_VISIBLE_DEVICES_VALUE="$(config_value CUDA_VISIBLE_DEVICES)"

  [[ "$COMFY_ENV_BACKEND" == "uv" ]] || die "only COMFY_ENV_BACKEND=uv is supported in this stage" 2
}

require_uv() {
  command -v "$UV_BIN" >/dev/null 2>&1 || die "uv not found; install uv first" 2
}

require_venv() {
  [[ -x "$PYTHON_BIN" ]] || die "$PYTHON_BIN not found; run ./scripts/local.sh bootstrap" 2
}

require_manager() {
  require_venv
  PYTHONPATH="$COMFY_DIR${PYTHONPATH:+:$PYTHONPATH}" "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1 || die "comfyui_manager is not importable in ComfyUI runtime; run ./scripts/nodes.sh status" 1
import comfyui_manager
if not comfyui_manager.__file__ or not comfyui_manager.__file__.endswith("__init__.py"):
    raise SystemExit(1)
PY
}

require_loopback_host() {
  case "$COMFY_HOST" in
    127.0.0.1|localhost|::1) ;;
    *) die "local.sh only allows loopback COMFY_HOST in this stage: $COMFY_HOST" 2 ;;
  esac
}

pid_of() {
  [[ -f "$PID_FILE" ]] && cat "$PID_FILE" 2>/dev/null || true
}

is_pid_running() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

pid_command() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  ps -ww -p "$pid" -o command= 2>/dev/null || ps -p "$pid" -o command= 2>/dev/null || true
}

pid_is_comfyui() {
  local pid="$1"
  local command
  command="$(pid_command "$pid")"
  case "$command" in
    *"$PYTHON_BIN"*" main.py "*"--enable-manager"*"--listen"*"${COMFY_HOST}"*"--port"*"${COMFY_PORT}"*) return 0 ;;
    *) return 1 ;;
  esac
}

port_owner_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$COMFY_PORT" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
  fi
}

port_owner_probe_available() {
  command -v lsof >/dev/null 2>&1
}

system_stats_url() {
  printf 'http://%s:%s/system_stats' "$COMFY_HOST" "$COMFY_PORT"
}

system_stats_ready() {
  curl -fsS --max-time 2 "$(system_stats_url)" >/dev/null 2>&1
}

stop_pid() {
  local pid="$1"
  event "STOPPING" "comfyui" "pid=$pid"
  kill "$pid" 2>/dev/null || true
  local elapsed=0
  while is_pid_running "$pid"; do
    if (( elapsed >= 15 )); then
      die "ComfyUI pid=$pid did not exit after TERM; inspect manually before using kill -9" 4
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  rm -f "$PID_FILE"
  event "STOPPED" "comfyui" ""
}

wait_for_url() {
  local url="$1"
  local timeout="$2"
  local elapsed=0
  while true; do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    if (( elapsed >= timeout )); then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

bootstrap() {
  load_config
  require_uv
  [[ -d "$COMFY_DIR" ]] || die "ComfyUI submodule not found" 2
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  section "Bootstrap"
  if [[ -x "$PYTHON_BIN" ]]; then
    event "EXISTS" ".venv" "$PYTHON_BIN"
  else
    event "CREATE" ".venv" "python ${COMFY_PYTHON_VERSION}"
    "$UV_BIN" venv --python "$COMFY_PYTHON_VERSION" "$ROOT_DIR/.venv"
  fi

  section "Install PyTorch"
  local torch_args=(pip install --python "$PYTHON_BIN")
  if [[ "${TORCH_PRE_VALUE:-false}" == "true" ]]; then
    torch_args+=(--pre)
  fi
  torch_args+=(torch torchvision torchaudio)
  if [[ -n "${TORCH_INDEX_URL_VALUE:-}" ]]; then
    torch_args+=(--index-url "$TORCH_INDEX_URL_VALUE")
  fi
  "$UV_BIN" "${torch_args[@]}"

  section "Install ComfyUI"
  "$UV_BIN" pip install --python "$PYTHON_BIN" -r "$COMFY_DIR/requirements.txt"

  section "Install Manager"
  "$ROOT_DIR/scripts/nodes.sh" install manager

  section "Ready"
  "$PYTHON_BIN" - <<'PY'
import sys
import torch
print("python:", sys.version.split()[0])
print("torch:", torch.__version__)
print("cuda:", torch.cuda.is_available())
print("mps:", getattr(torch.backends, "mps", None).is_available() if hasattr(torch.backends, "mps") else False)
PY
}

start() {
  load_config
  require_venv
  require_manager
  require_loopback_host
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  local pid
  pid="$(pid_of)"
  if is_pid_running "$pid" && pid_is_comfyui "$pid"; then
    event "RUNNING" "comfyui" "pid=$pid url=http://${COMFY_HOST}:${COMFY_PORT}"
    return
  elif is_pid_running "$pid"; then
    rm -f "$PID_FILE"
    event "STALE" "comfyui" "pid=$pid is not ComfyUI; removed pid file"
  fi
  rm -f "$PID_FILE"
  local owner
  owner="$(port_owner_pid)"
  if [[ -n "$owner" ]]; then
    if pid_is_comfyui "$owner"; then
      if ! system_stats_ready; then
        die "port ${COMFY_PORT} is owned by ComfyUI pid=${owner}, but /system_stats is not ready" 4
      fi
      echo "$owner" > "$PID_FILE"
      event "RUNNING" "comfyui" "pid=$owner url=http://${COMFY_HOST}:${COMFY_PORT}"
      return
    fi
    die "port ${COMFY_PORT} is already used by pid=${owner}" 4
  fi

  section "Start"
  event "LOG" "comfyui" "$LOG_FILE"
  event "MANAGER" "enabled" "upstream checks or previously scheduled Manager tasks may run"
  local cmd=("$PYTHON_BIN" main.py --enable-manager --listen "$COMFY_HOST" --port "$COMFY_PORT")
  if [[ -n "${CUDA_VISIBLE_DEVICES_VALUE:-}" ]]; then
    cmd+=(--cuda-device "$CUDA_VISIBLE_DEVICES_VALUE")
  fi
  if [[ -n "${COMFY_OUTPUT_ROOT:-}" ]]; then
    case "$COMFY_OUTPUT_ROOT" in
      /*) cmd+=(--output-directory "$COMFY_OUTPUT_ROOT") ;;
      *) cmd+=(--output-directory "$ROOT_DIR/$COMFY_OUTPUT_ROOT") ;;
    esac
  fi
  (
    cd "$COMFY_DIR"
    env HF_ENDPOINT="${HF_ENDPOINT_VALUE:-}" "${cmd[@]}" &
    child_pid=$!
    echo "$child_pid" > "$PID_FILE"
    wait "$child_pid"
  ) > "$LOG_FILE" 2>&1 &
  local elapsed=0
  while [[ ! -s "$PID_FILE" ]]; do
    if (( elapsed >= 5 )); then
      die "ComfyUI child pid was not written; inspect ./scripts/local.sh logs" 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  pid="$(pid_of)"
  sleep 1
  if ! is_pid_running "$pid"; then
    tail -n 80 "$LOG_FILE" >&2 2>/dev/null || true
    rm -f "$PID_FILE"
    die "ComfyUI failed to stay running; inspect ./scripts/local.sh logs" 1
  fi

  local url
  url="$(system_stats_url)"
  if wait_for_url "$url" 90; then
    event "READY" "comfyui" "http://${COMFY_HOST}:${COMFY_PORT}"
  else
    tail -n 80 "$LOG_FILE" >&2 2>/dev/null || true
    die "ComfyUI did not become ready at $url" 1
  fi
}

stop() {
  load_config
  require_loopback_host
  section "Stop"
  local pid
  pid="$(pid_of)"
  if [[ -z "$pid" ]]; then
    local owner
    owner="$(port_owner_pid)"
    if [[ -n "$owner" ]] && pid_is_comfyui "$owner"; then
      event "RECOVER" "comfyui" "no pid file; using port owner pid=$owner"
      stop_pid "$owner"
      return
    fi
    event "STOPPED" "comfyui" "no pid file"
    return
  fi
  if ! is_pid_running "$pid"; then
    rm -f "$PID_FILE"
    event "STALE" "comfyui" "removed pid=$pid"
    local owner
    owner="$(port_owner_pid)"
    if [[ -n "$owner" ]] && pid_is_comfyui "$owner"; then
      event "RECOVER" "comfyui" "using port owner pid=$owner"
      stop_pid "$owner"
    fi
    return
  fi
  if ! pid_is_comfyui "$pid"; then
    rm -f "$PID_FILE"
    event "STALE" "comfyui" "pid=$pid is not ComfyUI; removed pid file"
    local owner
    owner="$(port_owner_pid)"
    if [[ -n "$owner" ]] && pid_is_comfyui "$owner"; then
      event "RECOVER" "comfyui" "using port owner pid=$owner"
      stop_pid "$owner"
    fi
    return
  fi
  stop_pid "$pid"
}

status() {
  load_config
  require_loopback_host
  section "Status"
  local pid
  pid="$(pid_of)"
  if is_pid_running "$pid" && pid_is_comfyui "$pid"; then
    event "RUNNING" "comfyui" "pid=$pid"
  elif [[ -n "$pid" ]]; then
    event "STALE" "comfyui" "pid=$pid"
    local owner
    owner="$(port_owner_pid)"
    if [[ -n "$owner" ]] && pid_is_comfyui "$owner"; then
      event "RUNNING" "port-owner" "pid=$owner"
    elif [[ -n "$owner" ]]; then
      event "BLOCKED" "port-owner" "pid=$owner is not ComfyUI"
    else
      event "STOPPED" "comfyui" "pid file stale; no listener"
    fi
  else
    local owner
    if port_owner_probe_available; then
      owner="$(port_owner_pid)"
      if [[ -n "$owner" ]] && pid_is_comfyui "$owner"; then
        event "RUNNING" "port-owner" "pid=$owner"
      elif [[ -n "$owner" ]]; then
        event "BLOCKED" "port-owner" "pid=$owner is not ComfyUI"
      else
        event "STOPPED" "comfyui" "pid=-"
      fi
    else
      event "UNKNOWN" "port-owner" "lsof not found"
    fi
  fi
  event "URL" "web" "http://${COMFY_HOST}:${COMFY_PORT}"
  event "LOG" "file" "$LOG_FILE"
  if system_stats_ready; then
    event "READY" "system_stats" "ok"
  else
    event "DOWN" "system_stats" "not reachable"
  fi
}

logs() {
  [[ -f "$LOG_FILE" ]] || die "$LOG_FILE not found" 2
  tail -f "$LOG_FILE"
}

command="${1:-}"
case "$command" in
  -h|--help|help)
    usage
    ;;
  bootstrap)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage bootstrap; exit 0; fi
    parse_config_args bootstrap "$@"
    bootstrap
    ;;
  start)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage start; exit 0; fi
    parse_config_args start "$@"
    acquire_lifecycle_lock
    start
    ;;
  stop)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage stop; exit 0; fi
    parse_config_args stop "$@"
    acquire_lifecycle_lock
    stop
    ;;
  restart)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage restart; exit 0; fi
    parse_config_args restart "$@"
    acquire_lifecycle_lock
    stop
    start
    ;;
  status)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage status; exit 0; fi
    parse_config_args status "$@"
    status
    ;;
  logs)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage logs; exit 0; fi
    [[ "$#" -eq 0 ]] || die "logs takes no arguments" 2
    logs
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
