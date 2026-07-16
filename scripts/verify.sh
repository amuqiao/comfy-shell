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
  5. 默认 .env / 显式 --profile / 显式 remote 参数合同 smoke
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
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/comfy-shell-pycache" python3 -m py_compile \
  "${ROOT_DIR}/scripts/lib/models_cli.py" \
  "${ROOT_DIR}/scripts/lib/remote_gpu_format.py"

section "Help Smoke"
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
for subcmd in list inspect status verify plan download; do
  "${ROOT_DIR}/scripts/models.sh" "$subcmd" -h >/dev/null
done
for subcmd in sync bootstrap start stop restart status logs models ready tunnel gpu; do
  "${ROOT_DIR}/scripts/remote.sh" "$subcmd" -h >/dev/null
done

section "Read-only Smoke"
COMFY_DEVICE=cpu "${ROOT_DIR}/scripts/check_env.sh" --no-network >/dev/null
COMFY_DEVICE=cpu "${ROOT_DIR}/scripts/check_env.sh" --profile .env.example --no-network >/dev/null
"${ROOT_DIR}/scripts/models.sh" list >/dev/null
"${ROOT_DIR}/scripts/models.sh" inspect "${ROOT_DIR}/.data/nodes/批量照片转绘复古动漫风格（LoRA+ControlNet+UltimateSDUpscale）.png" >/dev/null
bad_workflow_file="$(mktemp "${TMPDIR:-/tmp}/comfy-shell-bad-workflow.XXXXXX")"
printf '{bad-json\n' >"$bad_workflow_file"
set +e
bad_workflow_output="$("${ROOT_DIR}/scripts/models.sh" inspect "$bad_workflow_file" 2>&1 >/dev/null)"
bad_workflow_status=$?
set -e
rm -f "$bad_workflow_file"
if [[ "$bad_workflow_status" -ne 2 ]]; then
  die "models.sh inspect bad workflow returned $bad_workflow_status, expected 2" 1
fi
if printf '%s\n' "$bad_workflow_output" | grep -q 'Traceback'; then
  die "models.sh inspect bad workflow printed Python traceback" 1
fi
"${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core --profile .env.example >/dev/null
"${ROOT_DIR}/scripts/models.sh" plan retro-anime-photo-core --profile .env.example >/dev/null
expect_status 1 "${ROOT_DIR}/scripts/models.sh" verify retro-anime-photo-core --profile .env.example
expect_status 2 "${ROOT_DIR}/scripts/models.sh" download retro-anime-photo-core --profile .env.example
"${ROOT_DIR}/scripts/remote.sh" tunnel --profile .env.example --local-port 18188 --dry-run >/dev/null
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile .env.example inspect .data/nodes/workflow.png
expect_status 2 "${ROOT_DIR}/scripts/local.sh" status --unknown
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" sync --profile .env.example
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" status --profile .env.example --unknown
expect_status 2 "${ROOT_DIR}/scripts/models.sh" list --profile .env.example
if printf '' | python3 "${ROOT_DIR}/scripts/lib/remote_gpu_format.py" --host smoke --json >/dev/null 2>&1; then
  die "remote_gpu_format.py accepted an empty snapshot" 1
fi

section "Config Contract Smoke"
contract_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/comfy-shell-verify.XXXXXX")"
trap 'rm -rf "$contract_tmp_dir"' EXIT
contract_profile="$contract_tmp_dir/profile.env"
cat >"$contract_profile" <<'EOF'
COMFY_PROFILE=verify-contract
COMFY_ENV_BACKEND=uv
COMFY_PYTHON=3.12.13
COMFY_DEVICE=cpu
COMFY_HOST=127.0.0.1
COMFY_PORT=18188
COMFY_MODEL_ROOT=/tmp/comfy-shell-profile-models
COMFY_OUTPUT_ROOT=/tmp/comfy-shell-profile-output
REMOTE_HOST=verify@example.com
REMOTE_DIR=/tmp/comfy-shell-remote
REMOTE_READY_URL=http://127.0.0.1:18188
REMOTE_TUNNEL_LOCAL_PORT=18188
REMOTE_TUNNEL_REMOTE_HOST=127.0.0.1
REMOTE_TUNNEL_REMOTE_PORT=18189
REMOTE_LOG_TAIL=42
REMOTE_GPU_CONNECT_TIMEOUT=3
EOF

if [[ -f "$ROOT_DIR/.env" ]]; then
  COMFY_DEVICE=cpu "${ROOT_DIR}/scripts/local.sh" status >/dev/null
  "${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core >/dev/null
  if [[ -n "$(env_value_from REMOTE_HOST "$ROOT_DIR/.env")" && -n "$(env_value_from REMOTE_DIR "$ROOT_DIR/.env")" ]]; then
    "${ROOT_DIR}/scripts/remote.sh" tunnel --dry-run >/dev/null
  else
    event "SKIP" "default-remote" ".env has no REMOTE_HOST/REMOTE_DIR"
  fi
else
  event "SKIP" "default-.env" ".env not found"
fi

"${ROOT_DIR}/scripts/local.sh" status --profile "$contract_profile" >/dev/null
runtime_python_profile="$contract_tmp_dir/runtime-python.env"
cat >"$runtime_python_profile" <<'EOF'
COMFY_PROFILE=verify-runtime-python
COMFY_ENV_BACKEND=uv
COMFY_PYTHON=3.12
COMFY_DEVICE=cpu
COMFY_HOST=127.0.0.1
COMFY_PORT=18188
COMFY_MODEL_ROOT=/tmp/comfy-shell-runtime-python-models
COMFY_OUTPUT_ROOT=/tmp/comfy-shell-runtime-python-output
EOF
"${ROOT_DIR}/scripts/local.sh" status --profile "$runtime_python_profile" >/dev/null
if ! "${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core --profile "$contract_profile" | grep -q '/tmp/comfy-shell-profile-models'; then
  die "models.sh did not read COMFY_MODEL_ROOT from explicit --profile file" 1
fi
if ! COMFY_MODEL_ROOT=/tmp/comfy-shell-env-models "${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core --profile "$contract_profile" | grep -q '/tmp/comfy-shell-env-models'; then
  die "exported COMFY_MODEL_ROOT did not override explicit --profile file" 1
fi
missing_model_profile="$contract_tmp_dir/no-model-root.env"
cat >"$missing_model_profile" <<'EOF'
COMFY_PROFILE=verify-missing-model-root
COMFY_ENV_BACKEND=uv
COMFY_PYTHON=3.12.13
COMFY_DEVICE=cpu
COMFY_HOST=127.0.0.1
COMFY_PORT=18188
COMFY_OUTPUT_ROOT=/tmp/comfy-shell-missing-model-output
EOF
"${ROOT_DIR}/scripts/models.sh" list >/dev/null
set +e
missing_model_output="$("${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core --profile "$missing_model_profile" 2>&1)"
missing_model_status=$?
set -e
if [[ "$missing_model_status" -ne 2 ]]; then
  die "models.sh plan without COMFY_MODEL_ROOT returned $missing_model_status, expected 2" 1
fi
if printf '%s\n' "$missing_model_output" | grep -q '^TARGET'; then
  die "models.sh plan without COMFY_MODEL_ROOT printed a target path" 1
fi
expect_status 2 "${ROOT_DIR}/scripts/models.sh" status --profile "$missing_model_profile"
expect_status 2 "${ROOT_DIR}/scripts/models.sh" download heroine-i2v-core --profile "$missing_model_profile"
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" bootstrap --profile "$contract_profile"
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" sync --profile "$contract_profile"
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" tunnel --profile "$contract_tmp_dir/missing.env" --dry-run
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models plan retro-anime-photo-core --profile "$contract_profile"
ssh_stub_dir="$contract_tmp_dir/bin"
ssh_argv_file="$contract_tmp_dir/ssh-argv.txt"
mkdir -p "$ssh_stub_dir"
cat >"$ssh_stub_dir/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$COMFY_SHELL_SSH_ARGV_FILE"
EOF
chmod +x "$ssh_stub_dir/ssh"
COMFY_SHELL_SSH_ARGV_FILE="$ssh_argv_file" PATH="$ssh_stub_dir:$PATH" \
  "${ROOT_DIR}/scripts/remote.sh" models --profile "$contract_profile" plan retro-anime-photo-core >/dev/null
if ! grep -Fxq 'verify@example.com' "$ssh_argv_file"; then
  die "remote.sh models did not pass configured REMOTE_HOST to ssh" 1
fi
if ! grep -Fxq 'cd /tmp/comfy-shell-remote && ./scripts/models.sh plan retro-anime-photo-core' "$ssh_argv_file"; then
  die "remote.sh models did not build the expected remote models.sh command" 1
fi
missing_remote_profile="$contract_tmp_dir/no-remote.env"
cat >"$missing_remote_profile" <<'EOF'
COMFY_PROFILE=verify-missing-remote
COMFY_ENV_BACKEND=uv
COMFY_PYTHON=3.12.13
COMFY_DEVICE=cpu
COMFY_HOST=127.0.0.1
COMFY_PORT=18188
COMFY_MODEL_ROOT=/tmp/comfy-shell-missing-remote-models
COMFY_OUTPUT_ROOT=/tmp/comfy-shell-missing-remote-output
EOF
set +e
missing_remote_output="$("${ROOT_DIR}/scripts/remote.sh" status --profile "$missing_remote_profile" 2>&1 >/dev/null)"
missing_remote_status=$?
set -e
if [[ "$missing_remote_status" -ne 2 ]]; then
  die "remote.sh missing REMOTE_* returned $missing_remote_status, expected 2" 1
fi
if ! printf '%s\n' "$missing_remote_output" | grep -q 'REMOTE_HOST, REMOTE_DIR are not configured'; then
  die "remote.sh missing REMOTE_* did not explain missing keys" 1
fi
if printf '%s\n' "$missing_remote_output" | grep -q '^用法:'; then
  die "remote.sh missing REMOTE_* printed full usage instead of concise config guidance" 1
fi
set +e
missing_remote_host_output="$("${ROOT_DIR}/scripts/remote.sh" tunnel --profile "$missing_remote_profile" --dry-run 2>&1 >/dev/null)"
missing_remote_host_status=$?
set -e
if [[ "$missing_remote_host_status" -ne 2 ]]; then
  die "remote.sh missing REMOTE_HOST returned $missing_remote_host_status, expected 2" 1
fi
if ! printf '%s\n' "$missing_remote_host_output" | grep -q 'REMOTE_HOST is not configured'; then
  die "remote.sh host-only missing REMOTE_HOST did not explain missing key" 1
fi
if printf '%s\n' "$missing_remote_host_output" | grep -q '^用法:'; then
  die "remote.sh host-only missing REMOTE_HOST printed full usage instead of concise config guidance" 1
fi
if ! "${ROOT_DIR}/scripts/remote.sh" tunnel --profile "$contract_profile" --dry-run | grep -q '18188:127.0.0.1:18189'; then
  die "remote.sh did not read REMOTE_TUNNEL_* from explicit --profile file" 1
fi
if ! REMOTE_TUNNEL_LOCAL_PORT=18190 "${ROOT_DIR}/scripts/remote.sh" tunnel --profile "$contract_profile" --dry-run | grep -q '18190:127.0.0.1:18189'; then
  die "exported REMOTE_TUNNEL_LOCAL_PORT did not override explicit --profile file" 1
fi
if ! "${ROOT_DIR}/scripts/remote.sh" tunnel --profile "$contract_profile" --host override@example.com --local-port 18191 --remote-host localhost --remote-port 18192 --dry-run | grep -q '18191:localhost:18192 override@example.com'; then
  die "remote.sh CLI tunnel overrides did not win over profile config" 1
fi
set +e
missing_models_output="$("${ROOT_DIR}/scripts/remote.sh" models --profile "$missing_remote_profile" plan retro-anime-photo-core 2>&1 >/dev/null)"
missing_models_status=$?
set -e
if [[ "$missing_models_status" -ne 2 ]]; then
  die "remote.sh models missing REMOTE_* returned $missing_models_status, expected 2" 1
fi
if ! printf '%s\n' "$missing_models_output" | grep -q 'REMOTE_HOST, REMOTE_DIR are not configured'; then
  die "remote.sh models missing REMOTE_* did not explain missing keys" 1
fi

section "Diff Check"
git -C "$ROOT_DIR" diff --check

printf 'check ok\n'
