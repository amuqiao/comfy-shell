#!/usr/bin/env bash
# verify.sh - project script verification entry

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
用法:
  ./scripts/verify.sh check
  ./scripts/verify.sh -h|--help

作用域:
  执行当前仓库 scripts/ 的最小可重复校验。用于修改脚本后的本地 smoke 验证。

不负责:
  不启动 ComfyUI, 不访问远端服务器, 不下载模型, 不安装依赖。

check 会执行:
  1. shell 入口语法检查
  2. 可用时执行 shellcheck
  3. Python helper 语法检查
  4. scripts 入口 help smoke
  5. profile 列表只读 smoke
  6. git diff --check

输出:
  stdout 输出阶段和 check ok。
  stderr 输出参数错误、校验失败或下层工具诊断。

副作用与保护边界:
  只读。不写项目文件, 不启动进程, 不访问网络。

Exit Codes:
  0  成功。
  1  校验不通过或下层检查失败。
  2  参数、用法或前置条件错误。
  其他非 0 由下层工具透传。
EOF
}

cmd="${1:-}"
case "$cmd" in
  -h|--help)
    usage
    exit 0
    ;;
  check)
    shift
    [[ "$#" -eq 0 ]] || usage_error "check takes no arguments" usage
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    usage_error "unknown command: $cmd" usage
    ;;
esac

section "Shell Syntax"
bash -n "${ROOT_DIR}"/scripts/*.sh "${ROOT_DIR}"/scripts/lib/*.sh

section "Shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${ROOT_DIR}"/scripts/*.sh "${ROOT_DIR}"/scripts/lib/*.sh
else
  event "SKIP" "shellcheck" "not found"
fi

section "Python Syntax"
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/comfy-shell-pycache" python3 -m py_compile "${ROOT_DIR}/scripts/lib/remote_gpu_format.py"

section "Help Smoke"
"${ROOT_DIR}/scripts/env.sh" -h >/dev/null
"${ROOT_DIR}/scripts/check_env.sh" -h >/dev/null
"${ROOT_DIR}/scripts/dev.sh" -h >/dev/null
"${ROOT_DIR}/scripts/nodes.sh" -h >/dev/null
"${ROOT_DIR}/scripts/models.sh" -h >/dev/null
"${ROOT_DIR}/scripts/tunnel.sh" -h >/dev/null
"${ROOT_DIR}/scripts/remote.sh" -h >/dev/null
"${ROOT_DIR}/scripts/remote-gpu.sh" -h >/dev/null
"${ROOT_DIR}/scripts/remote-dev.sh" -h >/dev/null
"${ROOT_DIR}/scripts/verify.sh" -h >/dev/null

section "Read-only Smoke"
"${ROOT_DIR}/scripts/env.sh" profiles >/dev/null

section "Diff Check"
git -C "$ROOT_DIR" diff --check

printf 'check ok\n'
