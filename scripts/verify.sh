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
for subcmd in check list inspect status verify plan download; do
  "${ROOT_DIR}/scripts/models.sh" "$subcmd" -h >/dev/null
done
for subcmd in sync bootstrap start stop restart status logs models ready tunnel gpu; do
  "${ROOT_DIR}/scripts/remote.sh" "$subcmd" -h >/dev/null
done

section "Read-only Smoke"
COMFY_DEVICE=cpu "${ROOT_DIR}/scripts/check_env.sh" --no-network >/dev/null
COMFY_DEVICE=cpu "${ROOT_DIR}/scripts/check_env.sh" --profile .env.example --no-network >/dev/null
"${ROOT_DIR}/scripts/models.sh" check >/dev/null
COMFY_MODEL_ROOT='' "${ROOT_DIR}/scripts/models.sh" check >/dev/null
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
read_only_model_profile="$(mktemp "${TMPDIR:-/tmp}/comfy-shell-model-profile.XXXXXX")"
cat >"$read_only_model_profile" <<'EOF'
COMFY_MODEL_ROOT=/tmp/comfy-shell-read-only-models
EOF
"${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core --profile "$read_only_model_profile" >/dev/null
"${ROOT_DIR}/scripts/models.sh" plan retro-anime-photo-core --profile "$read_only_model_profile" >/dev/null
expect_status 1 "${ROOT_DIR}/scripts/models.sh" verify retro-anime-photo-core --profile "$read_only_model_profile"
expect_status 2 "${ROOT_DIR}/scripts/models.sh" download
expect_status 2 "${ROOT_DIR}/scripts/models.sh" check --profile "$read_only_model_profile"
expect_status 2 "${ROOT_DIR}/scripts/models.sh" check retro-anime-photo-core
expect_status 2 "${ROOT_DIR}/scripts/models.sh" list --profile "$read_only_model_profile"
rm -f "$read_only_model_profile"
"${ROOT_DIR}/scripts/remote.sh" tunnel --profile .env.example --local-port 18188 --dry-run >/dev/null
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile .env.example inspect .data/nodes/workflow.png
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile .env.example logs
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile .env.example logs retro-anime-photo-core --tail nope
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile .env.example logs retro-anime-photo-core --tail
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile .env.example plan retro-anime-photo-core --detach
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile .env.example download retro-anime-photo-core --profile .env.example
expect_status 2 "${ROOT_DIR}/scripts/local.sh" status --unknown
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" sync --profile .env.example
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" status --profile .env.example --unknown
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
  "${ROOT_DIR}/scripts/models.sh" check >/dev/null
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
hf_payload="model-data"
hf_sha="$(printf '%s' "$hf_payload" | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
hf_size="$(printf '%s' "$hf_payload" | wc -c | tr -d ' ')"
hf_catalog="$contract_tmp_dir/hf-catalog.yaml"
cat >"$hf_catalog" <<EOF
version: 2
bundles:
  hf-endpoint-smoke:
    title: HF endpoint smoke
    models:
      - id: endpoint-file
        directory: checkpoints
        filename: endpoint.bin
        source:
          platform: huggingface
          repo: smoke/repo
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: endpoint.bin
          sha256: $hf_sha
          size_bytes: $hf_size
EOF
hf_profile="$contract_tmp_dir/hf-profile.env"
cat >"$hf_profile" <<'EOF'
COMFY_MODEL_ROOT=/tmp/comfy-shell-hf-endpoint-profile-models
HF_ENDPOINT=https://profile.example
EOF
hf_stub_dir="$contract_tmp_dir/hf-bin"
mkdir -p "$hf_stub_dir"
hf_stub="$hf_stub_dir/hf"
hf_endpoint_file="$contract_tmp_dir/hf-endpoint.txt"
cat >"$hf_stub" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "download" ]] || exit 2
remote_path="${3:-}"
local_dir=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --local-dir)
      local_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$remote_path" && -n "$local_dir" ]] || exit 2
printf '%s\n' "${HF_ENDPOINT:-}" >"$COMFY_SHELL_HF_ENDPOINT_FILE"
mkdir -p "$local_dir/$(dirname "$remote_path")"
printf 'model-data' >"$local_dir/$remote_path"
EOF
chmod +x "$hf_stub"
rm -rf /tmp/comfy-shell-hf-endpoint-profile-models /tmp/comfy-shell-hf-endpoint-env-models
COMFY_SHELL_HF_ENDPOINT_FILE="$hf_endpoint_file" CATALOG_FILE="$hf_catalog" HF_CLI="$hf_stub" \
  "${ROOT_DIR}/scripts/models.sh" download hf-endpoint-smoke --profile "$hf_profile" >/dev/null
if [[ "$(cat "$hf_endpoint_file")" != "https://profile.example" ]]; then
  die "models.sh download did not pass HF_ENDPOINT from profile to hf CLI" 1
fi
COMFY_SHELL_HF_ENDPOINT_FILE="$hf_endpoint_file" CATALOG_FILE="$hf_catalog" HF_CLI="$hf_stub" \
  COMFY_MODEL_ROOT=/tmp/comfy-shell-hf-endpoint-env-models HF_ENDPOINT=https://env.example \
  "${ROOT_DIR}/scripts/models.sh" download hf-endpoint-smoke --profile "$hf_profile" >/dev/null
if [[ "$(cat "$hf_endpoint_file")" != "https://env.example" ]]; then
  die "exported HF_ENDPOINT did not override profile for hf CLI" 1
fi
civitai_payload_file="$contract_tmp_dir/civitai-payload.bin"
printf 'civitai-model-data' >"$civitai_payload_file"
civitai_sha="$(python3 - "$civitai_payload_file" <<'PY'
import hashlib
import pathlib
import sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
civitai_size="$(wc -c <"$civitai_payload_file" | tr -d ' ')"
civitai_catalog="$contract_tmp_dir/civitai-catalog.yaml"
cat >"$civitai_catalog" <<EOF
version: 2
bundles:
  civitai-smoke:
    title: Civitai smoke
    models:
      - id: civitai-file
        directory: loras
        filename: civitai.bin
        source:
          platform: civitai
          page_url: https://civitai.com/models/0/smoke
        download:
          mode: auto
          method: civitai
          url: file://$civitai_payload_file
          sha256: $civitai_sha
          size_bytes: $civitai_size
      - id: manual-file
        directory: vae
        filename: manual.bin
        source:
          platform: unknown
        download:
          mode: manual
          method: browser
          reason: smoke manual entry
      - id: blocked-file
        directory: controlnet
        filename: blocked.bin
        source:
          platform: huggingface
          page_url: https://huggingface.co/smoke/repo
        download:
          mode: blocked
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: blocked.bin
          reason: smoke blocked entry
EOF
civitai_profile="$contract_tmp_dir/civitai-profile.env"
cat >"$civitai_profile" <<'EOF'
COMFY_MODEL_ROOT=/tmp/comfy-shell-civitai-profile-models
EOF
rm -rf /tmp/comfy-shell-civitai-profile-models
set +e
civitai_download_output="$(CATALOG_FILE="$civitai_catalog" "${ROOT_DIR}/scripts/models.sh" download civitai-smoke --profile "$civitai_profile" 2>&1)"
civitai_download_status=$?
set -e
if [[ "$civitai_download_status" -ne 0 ]]; then
  printf '%s\n' "$civitai_download_output" >&2
  die "models.sh download did not skip manual/blocked entries while auto succeeded" 1
fi
if [[ ! -f /tmp/comfy-shell-civitai-profile-models/loras/civitai.bin ]]; then
  die "models.sh download did not write civitai method target file" 1
fi
for expected_summary in 'success: 1' 'manual: 1' 'blocked: 1' 'failed: 0'; do
  if ! printf '%s\n' "$civitai_download_output" | grep -q "$expected_summary"; then
    die "models.sh download summary missing: $expected_summary" 1
  fi
done
status_smoke_root="$contract_tmp_dir/status-models"
mkdir -p "$status_smoke_root/checkpoints" "$status_smoke_root/loras"
printf 'model-data' >"$status_smoke_root/checkpoints/ok.bin"
status_ok_sha="$(python3 - "$status_smoke_root/checkpoints/ok.bin" <<'PY'
import hashlib
import pathlib
import sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
status_ok_size="$(wc -c <"$status_smoke_root/checkpoints/ok.bin" | tr -d ' ')"
status_catalog="$contract_tmp_dir/status-catalog.yaml"
cat >"$status_catalog" <<EOF
version: 2
bundles:
  status-a:
    title: Status A
    models:
      - id: shared-ok-a
        directory: checkpoints
        filename: ok.bin
        source:
          platform: huggingface
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: ok.bin
          sha256: $status_ok_sha
          size_bytes: $status_ok_size
      - id: missing-file
        directory: checkpoints
        filename: missing.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: file://$civitai_payload_file
          sha256: $civitai_sha
      - id: manual-file
        directory: loras
        filename: manual.bin
        source:
          platform: unknown
        download:
          mode: manual
          method: browser
          reason: status manual entry
      - id: blocked-file
        directory: loras
        filename: blocked.bin
        source:
          platform: huggingface
        download:
          mode: blocked
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: blocked.bin
          reason: status blocked entry
  status-b:
    title: Status B
    models:
      - id: shared-ok-b
        directory: checkpoints
        filename: ok.bin
        source:
          platform: huggingface
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: ok.bin
          sha256: $status_ok_sha
          size_bytes: $status_ok_size
EOF
status_profile="$contract_tmp_dir/status-profile.env"
cat >"$status_profile" <<EOF
COMFY_MODEL_ROOT=$status_smoke_root
EOF
set +e
status_smoke_output="$(CATALOG_FILE="$status_catalog" "${ROOT_DIR}/scripts/models.sh" status --profile "$status_profile" 2>&1)"
status_smoke_status=$?
set -e
if [[ "$status_smoke_status" -ne 1 ]]; then
  printf '%s\n' "$status_smoke_output" >&2
  die "models.sh status smoke returned $status_smoke_status, expected 1" 1
fi
for expected_status in 'ok: 1' 'missing: 1' 'manual: 1' 'blocked: 1' 'total_unique: 4' 'bundles: status-a, status-b'; do
  if ! printf '%s\n' "$status_smoke_output" | grep -q "$expected_status"; then
    printf '%s\n' "$status_smoke_output" >&2
    die "models.sh status summary missing: $expected_status" 1
  fi
done
mixed_mode_catalog="$contract_tmp_dir/mixed-mode-catalog.yaml"
cat >"$mixed_mode_catalog" <<EOF
version: 2
bundles:
  mixed-manual:
    title: Mixed Manual
    models:
      - id: shared-manual
        directory: checkpoints
        filename: shared.bin
        source:
          platform: unknown
        download:
          mode: manual
          method: browser
          reason: mixed manual entry
  mixed-auto:
    title: Mixed Auto
    models:
      - id: shared-auto
        directory: checkpoints
        filename: shared.bin
        source:
          platform: huggingface
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: shared.bin
          sha256: $status_ok_sha
          size_bytes: $status_ok_size
EOF
set +e
mixed_mode_output="$(CATALOG_FILE="$mixed_mode_catalog" "${ROOT_DIR}/scripts/models.sh" status --profile "$status_profile" 2>&1)"
mixed_mode_status=$?
set -e
if [[ "$mixed_mode_status" -ne 1 ]]; then
  printf '%s\n' "$mixed_mode_output" >&2
  die "models.sh status mixed-mode target returned $mixed_mode_status, expected 1" 1
fi
for expected_mixed in 'conflict: 1' 'download.mode differs:'; do
  if ! printf '%s\n' "$mixed_mode_output" | grep -q "$expected_mixed"; then
    printf '%s\n' "$mixed_mode_output" >&2
    die "models.sh status mixed-mode output missing: $expected_mixed" 1
  fi
done
for expected_mode in 'auto' 'manual'; do
  if ! printf '%s\n' "$mixed_mode_output" | grep -q "$expected_mode"; then
    printf '%s\n' "$mixed_mode_output" >&2
    die "models.sh status mixed-mode output missing mode: $expected_mode" 1
  fi
done
if printf '%s\n' "$mixed_mode_output" | grep -q './scripts/models.sh download mixed-manual'; then
  printf '%s\n' "$mixed_mode_output" >&2
  die "models.sh status suggested downloading the manual bundle for mixed target" 1
fi
old_schema_catalog="$contract_tmp_dir/old-schema-catalog.yaml"
cat >"$old_schema_catalog" <<EOF
version: 1
bundles:
  old-schema:
    title: Old schema
    models:
      - id: old-file
        directory: checkpoints
        filename: old.bin
        source: huggingface
        repo: smoke/repo
        path: old.bin
        sha256: $hf_sha
EOF
set +e
old_schema_output="$(CATALOG_FILE="$old_schema_catalog" "${ROOT_DIR}/scripts/models.sh" check 2>&1 >/dev/null)"
old_schema_status=$?
set -e
if [[ "$old_schema_status" -ne 2 ]]; then
  die "models.sh accepted old catalog schema, expected exit 2" 1
fi
if ! printf '%s\n' "$old_schema_output" | grep -q 'version must be 2'; then
  die "models.sh old schema rejection did not explain schema version" 1
fi
bad_civitai_url_catalog="$contract_tmp_dir/bad-civitai-url-catalog.yaml"
cat >"$bad_civitai_url_catalog" <<EOF
version: 2
bundles:
  bad-url:
    title: Bad URL
    models:
      - id: bad-url-file
        directory: loras
        filename: bad.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: not-a-url
          sha256: $civitai_sha
EOF
set +e
bad_civitai_url_output="$(CATALOG_FILE="$bad_civitai_url_catalog" "${ROOT_DIR}/scripts/models.sh" check 2>&1 >/dev/null)"
bad_civitai_url_status=$?
set -e
if [[ "$bad_civitai_url_status" -ne 2 ]]; then
  die "models.sh accepted bad civitai download.url, expected exit 2" 1
fi
if printf '%s\n' "$bad_civitai_url_output" | grep -q 'Traceback'; then
  die "models.sh bad civitai download.url printed Python traceback" 1
fi
bad_size_catalog="$contract_tmp_dir/bad-size-catalog.yaml"
cat >"$bad_size_catalog" <<EOF
version: 2
bundles:
  bad-size:
    title: Bad size
    models:
      - id: bad-size-file
        directory: loras
        filename: bad-size.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: file://$civitai_payload_file
          sha256: $civitai_sha
          size_bytes: nope
EOF
set +e
bad_size_output="$(CATALOG_FILE="$bad_size_catalog" "${ROOT_DIR}/scripts/models.sh" check 2>&1 >/dev/null)"
bad_size_status=$?
set -e
if [[ "$bad_size_status" -ne 2 ]]; then
  die "models.sh accepted bad size_bytes, expected exit 2" 1
fi
if printf '%s\n' "$bad_size_output" | grep -q 'Traceback'; then
  die "models.sh bad size_bytes printed Python traceback" 1
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
"${ROOT_DIR}/scripts/models.sh" check >/dev/null
set +e
missing_model_output="$("${ROOT_DIR}/scripts/models.sh" plan heroine-i2v-core --profile "$missing_model_profile" 2>&1)"
missing_model_status=$?
set -e
if [[ "$missing_model_status" -ne 2 ]]; then
  die "models.sh plan without COMFY_MODEL_ROOT returned $missing_model_status, expected 2" 1
fi
if printf '%s\n' "$missing_model_output" | grep -q '^target:'; then
  die "models.sh plan without COMFY_MODEL_ROOT printed a target path" 1
fi
expect_status 2 "${ROOT_DIR}/scripts/models.sh" status --profile "$missing_model_profile"
expect_status 2 "${ROOT_DIR}/scripts/models.sh" download heroine-i2v-core --profile "$missing_model_profile"
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" bootstrap --profile "$contract_profile"
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" sync --profile "$contract_profile"
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" tunnel --profile "$contract_tmp_dir/missing.env" --dry-run
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models plan retro-anime-photo-core --profile "$contract_profile"
expect_status 2 "${ROOT_DIR}/scripts/remote.sh" models --profile "$contract_profile" check retro-anime-photo-core
ssh_stub_dir="$contract_tmp_dir/bin"
ssh_argv_file="$contract_tmp_dir/ssh-argv.txt"
mkdir -p "$ssh_stub_dir"
cat >"$ssh_stub_dir/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$COMFY_SHELL_SSH_ARGV_FILE"
EOF
chmod +x "$ssh_stub_dir/ssh"
COMFY_SHELL_SSH_ARGV_FILE="$ssh_argv_file" PATH="$ssh_stub_dir:$PATH" \
  "${ROOT_DIR}/scripts/remote.sh" models --profile "$contract_profile" check >/dev/null
if ! grep -Fxq 'cd /tmp/comfy-shell-remote && ./scripts/models.sh check' "$ssh_argv_file"; then
  die "remote.sh models check did not build the expected remote models.sh command" 1
fi
COMFY_SHELL_SSH_ARGV_FILE="$ssh_argv_file" PATH="$ssh_stub_dir:$PATH" \
  "${ROOT_DIR}/scripts/remote.sh" models --profile "$contract_profile" plan retro-anime-photo-core >/dev/null
if ! grep -Fxq 'verify@example.com' "$ssh_argv_file"; then
  die "remote.sh models did not pass configured REMOTE_HOST to ssh" 1
fi
if ! grep -Fxq 'cd /tmp/comfy-shell-remote && ./scripts/models.sh plan retro-anime-photo-core' "$ssh_argv_file"; then
  die "remote.sh models did not build the expected remote models.sh command" 1
fi
COMFY_SHELL_SSH_ARGV_FILE="$ssh_argv_file" PATH="$ssh_stub_dir:$PATH" \
  "${ROOT_DIR}/scripts/remote.sh" models --profile "$contract_profile" download retro-anime-photo-core --detach >/dev/null
if ! grep -Fq 'nohup sh -c' "$ssh_argv_file"; then
  die "remote.sh models download --detach did not build a nohup shell wrapper" 1
fi
# shellcheck disable=SC2016
if ! grep -Fq './scripts/models.sh download "$bundle"' "$ssh_argv_file"; then
  die "remote.sh models download --detach did not keep the remote models.sh download argv" 1
fi
if ! grep -Fq 'models-download retro-anime-photo-core' "$ssh_argv_file"; then
  die "remote.sh models download --detach did not tag the remote process with the bundle" 1
fi
if ! grep -Fq '.run/models-download-retro-anime-photo-core.pid' "$ssh_argv_file"; then
  die "remote.sh models download --detach did not write the expected pid path" 1
fi
if ! grep -Fq 'logs/models-download-retro-anime-photo-core.log' "$ssh_argv_file"; then
  die "remote.sh models download --detach did not write the expected log path" 1
fi
COMFY_SHELL_SSH_ARGV_FILE="$ssh_argv_file" PATH="$ssh_stub_dir:$PATH" \
  "${ROOT_DIR}/scripts/remote.sh" models --profile "$contract_profile" logs retro-anime-photo-core >/dev/null
if ! grep -Fxq 'cd /tmp/comfy-shell-remote && if [ ! -f logs/models-download-retro-anime-photo-core.log ]; then printf "ERROR: remote model log not found: logs/models-download-retro-anime-photo-core.log\n" >&2; exit 2; fi; tail -n 42 logs/models-download-retro-anime-photo-core.log' "$ssh_argv_file"; then
  die "remote.sh models logs did not use REMOTE_LOG_TAIL from profile" 1
fi
COMFY_SHELL_SSH_ARGV_FILE="$ssh_argv_file" PATH="$ssh_stub_dir:$PATH" \
  "${ROOT_DIR}/scripts/remote.sh" models --profile "$contract_profile" logs retro-anime-photo-core --tail all --follow >/dev/null
if ! grep -Fxq 'cd /tmp/comfy-shell-remote && if [ ! -f logs/models-download-retro-anime-photo-core.log ]; then printf "ERROR: remote model log not found: logs/models-download-retro-anime-photo-core.log\n" >&2; exit 2; fi; tail -n +1 -F logs/models-download-retro-anime-photo-core.log' "$ssh_argv_file"; then
  die "remote.sh models logs --tail all --follow did not build the expected tail command" 1
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
