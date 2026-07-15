#!/usr/bin/env bash
# nodes.sh - manage ComfyUI-Manager readiness for comfy-shell

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFY_DIR="$ROOT_DIR/ComfyUI"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
UV_BIN="${UV_BIN:-uv}"

usage() {
  cat <<'EOF'
用法:
  ./scripts/nodes.sh <command> [target]
  ./scripts/nodes.sh -h|--help

作用域:
  管理本机 ComfyUI-Manager 可用性。当前 ComfyUI 版本通过 --enable-manager
  加载 comfyui_manager Python 包,因此 manager 安装等价于安装
  ComfyUI/manager_requirements.txt 到项目 .venv。

运行环境:
  Requires: Bash, uv, 仓库根目录 .venv/bin/python
  前置步骤: ./scripts/local.sh bootstrap 会自动调用 install manager。

命令:
  install manager     安装 ComfyUI-Manager 依赖
  status              查看 manager 依赖在 ComfyUI runtime 中是否可 import
  help                显示本帮助

不负责:
  不安装第三方 custom_nodes,不下载模型,不启动 ComfyUI。

配置与环境变量:
  PYTHON_BIN          指定项目 Python, 默认 .venv/bin/python
  UV_BIN              指定 uv 命令, 默认 uv
  UV_INDEX_URL        uv 自身读取的默认包索引, 可临时设为国内 PyPI 镜像

输出:
  install manager: uv 安装输出和安装后的 manager import 状态。
  status: comfyui_manager 在 ComfyUI runtime 中是否可 import。

副作用与保护边界:
  status 只读。
  install manager 会访问 Python 包索引并写入 .venv。
  不会 clone ComfyUI-Manager 到 custom_nodes, 不会安装第三方 custom_nodes。

常用示例:
  ./scripts/nodes.sh status
  ./scripts/nodes.sh install manager
  UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple ./scripts/nodes.sh install manager

Exit Codes:
  0  成功
  1  manager 不可 import 或安装失败
  2  缺少 command、非法参数、uv/.venv/manager_requirements.txt 缺失
EOF
}

command_usage() {
  local name="$1"
  case "$name" in
    install-manager)
      cat <<'EOF'
用法:
  ./scripts/nodes.sh install manager
  ./scripts/nodes.sh install manager -h|--help

作用域:
  安装 ComfyUI/manager_requirements.txt 到仓库根目录 .venv。

前置条件:
  .venv 已存在; 否则先运行 ./scripts/local.sh bootstrap。
  uv 可用。

配置与环境变量:
  PYTHON_BIN          指定项目 Python, 默认 .venv/bin/python
  UV_BIN              指定 uv 命令, 默认 uv
  UV_INDEX_URL        可在命令前临时设置为国内 PyPI 镜像

副作用:
  会访问网络并写入 .venv。
  不会安装第三方 custom_nodes, 不会下载模型, 不会启动 ComfyUI。

常用示例:
  ./scripts/nodes.sh install manager
  UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple ./scripts/nodes.sh install manager
EOF
      ;;
    status)
      cat <<'EOF'
用法:
  ./scripts/nodes.sh status
  ./scripts/nodes.sh status -h|--help

作用域:
  只读检查项目 Python 在 ComfyUI runtime 中是否能 import comfyui_manager。

前置条件:
  .venv 已存在。

常用示例:
  ./scripts/nodes.sh status
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

require_file() {
  [[ -f "$1" ]] || die "$1 not found" 2
}

require_venv() {
  [[ -x "$PYTHON_BIN" ]] || die "$PYTHON_BIN not found; run ./scripts/local.sh bootstrap first" 2
}

install_manager() {
  require_file "$COMFY_DIR/manager_requirements.txt"
  require_venv
  command -v "$UV_BIN" >/dev/null 2>&1 || die "uv not found" 2
  section "Install Manager"
  event "INSTALL" "manager" "ComfyUI/manager_requirements.txt"
  "$UV_BIN" pip install --python "$PYTHON_BIN" -r "$COMFY_DIR/manager_requirements.txt"
  status_manager
}

status_manager() {
  require_venv
  section "Manager Status"
  PYTHONPATH="$COMFY_DIR${PYTHONPATH:+:$PYTHONPATH}" "$PYTHON_BIN" - <<'PY'
try:
    import comfyui_manager
except Exception as exc:
    print(f"MISSING    manager            comfyui_manager import failed: {exc}")
    raise SystemExit(1)
if not comfyui_manager.__file__ or not comfyui_manager.__file__.endswith("__init__.py"):
    print(f"MISSING    manager            unexpected module path: {comfyui_manager.__file__}")
    raise SystemExit(1)
print(f"OK         manager            {comfyui_manager.__file__}")
PY
}

command="${1:-}"
case "$command" in
  -h|--help|help)
    usage
    ;;
  install)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage install-manager; exit 0; fi
    target="${1:-}"
    [[ "$target" == "manager" ]] || die "install requires target: manager" 2
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage install-manager; exit 0; fi
    [[ "$#" -eq 0 ]] || die "install manager takes no arguments" 2
    install_manager
    ;;
  status)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then command_usage status; exit 0; fi
    [[ "$#" -eq 0 ]] || die "status takes no arguments" 2
    status_manager
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
