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
  4. scripts 入口和子命令 help smoke
  5. 显式 profile / 显式 remote 参数合同 smoke
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

expect_status() {
  local expected="$1"
  shift
  local status
  set +e
  "$@" >/dev/null 2>/dev/null
  status=$?
  set -e
  if [[ "$status" -ne "$expected" ]]; then
    printf 'ERROR: expected exit %s, got %s: ' "$expected" "$status" >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    exit 1
  fi
}

section "Shell Syntax"
bash -n "${ROOT_DIR}"/scripts/*.sh "${ROOT_DIR}"/scripts/lib/*.sh "${ROOT_DIR}"/tools/*.sh

section "Shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${ROOT_DIR}"/scripts/*.sh "${ROOT_DIR}"/scripts/lib/*.sh "${ROOT_DIR}"/tools/*.sh
else
  event "SKIP" "shellcheck" "not found"
fi

section "Python Syntax"
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/comfy-shell-pycache" python3 -m py_compile "${ROOT_DIR}/scripts/lib/remote_gpu_format.py"

section "Help Smoke"
"${ROOT_DIR}/scripts/env.sh" -h >/dev/null
"${ROOT_DIR}/scripts/check_env.sh" -h >/dev/null
"${ROOT_DIR}/scripts/local.sh" -h >/dev/null
"${ROOT_DIR}/scripts/nodes.sh" -h >/dev/null
"${ROOT_DIR}/scripts/models.sh" -h >/dev/null
"${ROOT_DIR}/scripts/remote.sh" -h >/dev/null
"${ROOT_DIR}/scripts/verify.sh" -h >/dev/null
"${ROOT_DIR}/tools/create-shell-submodule.sh" -h >/dev/null
for subcmd in bootstrap start stop restart status logs; do
  "${ROOT_DIR}/scripts/local.sh" "$subcmd" -h >/dev/null
done
for subcmd in list status plan download; do
  "${ROOT_DIR}/scripts/models.sh" "$subcmd" -h >/dev/null
done
for subcmd in sync bootstrap start stop restart status logs ready tunnel gpu; do
  "${ROOT_DIR}/scripts/remote.sh" "$subcmd" -h >/dev/null
done

section "Read-only Smoke"
"${ROOT_DIR}/scripts/env.sh" profiles >/dev/null
"${ROOT_DIR}/scripts/check_env.sh" --no-network >/dev/null
"${ROOT_DIR}/scripts/check_env.sh" --profile configs/profiles/macos-mps.env.example --no-network >/dev/null
"${ROOT_DIR}/scripts/models.sh" list >/dev/null
"${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core --profile configs/profiles/macos-mps.env.example >/dev/null
"${ROOT_DIR}/scripts/remote.sh" tunnel --host wangqiao@47.94.108.140 --local-port 18188 --remote-port 8188 --dry-run >/dev/null
expect_status 2 "${ROOT_DIR}/scripts/local.sh" status
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" sync --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" status --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" status --target server-a10
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" bootstrap --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --yes
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" start --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell --yes
expect_status 2 "${ROOT_DIR}/scripts/models.sh" list --profile .env
if printf '' | python3 "${ROOT_DIR}/scripts/lib/remote_gpu_format.py" --host smoke --json >/dev/null 2>&1; then
  die "remote_gpu_format.py accepted an empty snapshot" 1
fi

section "Diff Check"
git -C "$ROOT_DIR" diff --check

printf 'check ok\n'
