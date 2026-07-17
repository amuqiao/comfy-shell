#!/usr/bin/env bash
# models.sh - optional model catalog helper for comfy-shell

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

CATALOG_FILE="${CATALOG_FILE:-$ROOT_DIR/configs/models/catalog.yaml}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
HF_CLI="${HF_CLI:-hf}"

usage() {
  cat <<'EOF'
用法:
  ./scripts/models.sh check
  ./scripts/models.sh list
  ./scripts/models.sh list-models [bundle]
  ./scripts/models.sh inspect <workflow.png|workflow.json>
  ./scripts/models.sh status [bundle|--model MODEL_ID] [--profile FILE]
  ./scripts/models.sh verify [bundle|--model MODEL_ID] [--profile FILE]
  ./scripts/models.sh plan <bundle|--model MODEL_ID> [--profile FILE]
  ./scripts/models.sh download <bundle|--model MODEL_ID> [--profile FILE]
  ./scripts/models.sh info --model MODEL_ID [--profile FILE]
  ./scripts/models.sh install-upload --model MODEL_ID --file FILE [--profile FILE]
  ./scripts/models.sh -h|--help

作用域:
  可选的 ComfyUI 模型资产入口。读取 configs/models/catalog.yaml, 列出教程模型包,
  检查本地文件, 校验 hash, 预览下载计划, 并在用户显式执行时下载支持自动下载的模型。

不负责:
  不参与 local.sh bootstrap, 不自动下载模型, 不删除模型文件, 不安装 third-party custom_nodes,
  不修改 ComfyUI 已跟踪源码文件。

运行环境:
  Requires: Bash, 仓库根目录 .venv/bin/python
  check/list/list-models/status/verify/plan/download/info/install-upload 需要 .venv 中可 import PyYAML。
  check 只校验 catalog schema, 不读取 .env, 不检查模型文件, 不访问网络。
  inspect 只解析 PNG/JSON workflow metadata, 不访问网络, 不猜下载源。
  download.method=huggingface 需要 hf CLI; 优先使用 .venv/bin/hf, 其次使用 HF_CLI 或 PATH 中的 hf。
  download.method=civitai 使用 catalog 中的 Civitai API download URL。
  download.mode=manual 的条目只展示 source page、target 和原因, 不会自动下载。
  download.mode=blocked 的条目只展示阻塞原因, 不会自动下载。
  下载文件名必须和 catalog filename 一致; 不自动把相似文件重命名成 workflow 文件名。
  download.mode=auto 必须有 sha256; 下载后先校验 hash, 再写入 target。

命令:
  check               校验 catalog.yaml schema
  list                列出 catalog 中的 bundle
  list-models [bundle] 列出 catalog 中的模型 id 和 target
  inspect <file>      从 PNG/workflow JSON 提取模型引用
  status [bundle]     盘点 COMFY_MODEL_ROOT 中 catalog 声明的模型现状
  plan <bundle>       解释 catalog 中这个 bundle 应准备什么
  verify [bundle]     严格校验模型是否可复现
  download <bundle>   显式下载 bundle 中的模型文件
  info --model MODEL_ID 输出单模型 path/hash 信息
  install-upload       校验上传临时文件后安装到 target, 通常由 remote.sh 调用
  help                显示本帮助

配置与环境变量:
  status/verify/plan/download/info/install-upload 默认读取仓库根目录 .env。
  --profile FILE      status/verify/plan/download/info/install-upload 可显式指定其他配置文件。
  .env.example        只是配置示例; 运行配置默认真源是 .env。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。
  HF_ENDPOINT         可选; 只影响 download.method=huggingface。示例: https://hf-mirror.com
  CATALOG_FILE        可选, 覆盖 catalog 路径
  PYTHON_BIN          可选, 覆盖 Python 路径
  HF_CLI              可选, 覆盖 hf CLI 路径

副作用与保护边界:
  check/list/list-models/inspect/status/verify/plan/info 只读, 不访问网络。
  download 会创建模型子目录并写 auto 模型文件; 写入 COMFY_MODEL_ROOT 下的模型资产目录。
  manual/blocked 条目会跳过并输出下一步提示, 不会导致整个 download 提前中断。
  hash 不匹配、已有目标文件 hash 错误或网络下载失败时标记 failed, 不覆盖。
  download 必须由用户显式执行, 不修改 ComfyUI 已跟踪源码文件。
  所有相对模型路径按仓库根目录解析。

状态词:
  OK                  文件存在且 hash 正确。
  Missing             文件缺失, 但 catalog 已有可信自动下载信息; 执行 download。
  Manual              文件缺失, 但需要用户确认来源后手动下载到 target。
  Blocked             catalog 信息不足或策略阻塞; 先补来源/hash。
  Present Unverified  文件存在, 但 catalog 没有 hash 可校验。
  Bad                 文件存在但 hash、大小或内容不符合 catalog。
  Conflict            多个 bundle 对同一 target 的声明冲突。

常用示例:
  ./scripts/models.sh check
  ./scripts/models.sh list
  ./scripts/models.sh list-models retro-anime-photo-core
  # 下方命令前提: .env 已配置 COMFY_MODEL_ROOT
  ./scripts/models.sh status retro-anime-photo-core
  ./scripts/models.sh status --model isabelia-v10-checkpoint
  ./scripts/models.sh plan retro-anime-photo-core
  ./scripts/models.sh download --model isabelia-v10-checkpoint
  ./scripts/models.sh verify --model isabelia-v10-checkpoint

更多示例:
  docs/tutorials/models-cheatsheet.md

Exit Codes:
  0  成功
  1  status/verify 检查发现 missing、manual、blocked、bad、conflict 或未验证文件
  2  缺少 command、非法参数、catalog 缺失、Python/PyYAML/hf 缺失
  4  auto 下载运行失败
EOF
}

command_usage() {
  local name="$1"
  case "$name" in
    check)
      cat <<'EOF'
用法:
  ./scripts/models.sh check
  ./scripts/models.sh check -h|--help

作用域:
  校验 configs/models/catalog.yaml 的 schema。check 只读取 catalog,
  不读取 .env, 不需要 COMFY_MODEL_ROOT, 不检查模型文件, 不访问网络。

输出:
  catalog 路径、schema version、bundle 数量和模型条目数量。

常用示例:
  ./scripts/models.sh check
EOF
      ;;
    list)
      cat <<'EOF'
用法:
  ./scripts/models.sh list
  ./scripts/models.sh list -h|--help

作用域:
  列出 catalog 中的 bundle。list 会校验 catalog schema, 不读取配置文件。
EOF
      ;;
    list-models)
      cat <<'EOF'
用法:
  ./scripts/models.sh list-models [bundle]
  ./scripts/models.sh list-models -h|--help

作用域:
  列出 catalog 中的模型 id、target、download.mode 和 source。list-models 只读取 catalog,
  不读取配置文件, 不检查模型文件, 不访问网络。

常用示例:
  ./scripts/models.sh list-models
  ./scripts/models.sh list-models retro-anime-photo-core
EOF
      ;;
    inspect)
      cat <<'EOF'
用法:
  ./scripts/models.sh inspect <workflow.png|workflow.json>
  ./scripts/models.sh inspect -h|--help

作用域:
  从 ComfyUI PNG metadata 或 workflow JSON 中提取模型引用。只读, 不下载,
  不猜测来源, 不写 catalog。

输出:
  KIND、NODE、CLASS、FIELD、VALUE、SUGGESTED_DIR、NOTE。

常用示例:
  ./scripts/models.sh inspect .data/nodes/workflow.png
EOF
      ;;
    status)
      cat <<'EOF'
用法:
  ./scripts/models.sh status [bundle|--model MODEL_ID] [--profile FILE]
  ./scripts/models.sh status -h|--help

作用域:
  盘点 catalog 声明的模型在 COMFY_MODEL_ROOT 中的当前状态。
  不传 bundle 时检查全部 bundle, 并按 directory/filename 去重。
  有 sha256 时会校验 hash; manual/blocked 会显示原因、target 和建议动作。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  .env.example 只是配置示例, 不是默认运行配置。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。

常用示例:
  ./scripts/models.sh status
  ./scripts/models.sh status heroine-i2v-core
  ./scripts/models.sh status --model isabelia-v10-checkpoint
EOF
      ;;
    verify)
      cat <<'EOF'
用法:
  ./scripts/models.sh verify [bundle|--model MODEL_ID] [--profile FILE]
  ./scripts/models.sh verify -h|--help

作用域:
  严格校验 catalog 声明的模型是否可复现。只有文件存在且 sha256 正确才算 OK。
  manual、blocked、missing、bad、conflict 和 present_unverified 都会返回非 0。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  .env.example 只是配置示例, 不是默认运行配置。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。

常用示例:
  ./scripts/models.sh verify retro-anime-photo-core
  ./scripts/models.sh verify --model isabelia-v10-checkpoint
EOF
      ;;
    plan)
      cat <<'EOF'
用法:
  ./scripts/models.sh plan <bundle|--model MODEL_ID> [--profile FILE]
  ./scripts/models.sh plan -h|--help

作用域:
  解释 catalog: 输出 target、source、download.mode; auto 条目会输出 download.method, 不访问网络。
  plan 不检查文件是否已经存在; 要看磁盘现状请用 status。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  .env.example 只是配置示例, 不是默认运行配置。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。

常用示例:
  ./scripts/models.sh plan retro-anime-photo-core
  ./scripts/models.sh plan --model isabelia-v10-checkpoint
EOF
      ;;
    download)
      cat <<'EOF'
用法:
  ./scripts/models.sh download <bundle|--model MODEL_ID> [--profile FILE]
  ./scripts/models.sh download -h|--help

作用域:
  显式下载 bundle 中 download.mode=auto 的模型文件。
  manual/blocked 会跳过并在 Summary/Next 中提示, 不会提前中断整个 bundle。
  使用 --model 时只处理一个模型; manual/blocked 会返回非 0。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  .env.example 只是配置示例, 不是默认运行配置。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。
  HF_ENDPOINT         可选; 进程环境变量优先, 其次读取配置文件。

常用示例:
  ./scripts/models.sh download retro-anime-photo-core
  ./scripts/models.sh download --model isabelia-v10-checkpoint
  HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download retro-anime-photo-core
EOF
      ;;
    info)
      cat <<'EOF'
用法:
  ./scripts/models.sh info --model MODEL_ID [--profile FILE]
  ./scripts/models.sh info -h|--help

作用域:
  输出单个模型的 catalog 信息和本机 target 路径。用于人工核对和 remote.sh models upload。
  需要 COMFY_MODEL_ROOT, 不访问网络, 不写文件。

常用示例:
  ./scripts/models.sh info --model isabelia-v10-checkpoint
EOF
      ;;
    install-upload)
      cat <<'EOF'
用法:
  ./scripts/models.sh install-upload --model MODEL_ID --file FILE [--profile FILE]

作用域:
  校验 FILE 的 sha256/size 后安装到该 model 的 target。目标已存在且校验通过时跳过;
  目标已存在但校验失败时拒绝覆盖。通常由 remote.sh models upload 调用。
EOF
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

require_models_python() {
  [[ -x "$PYTHON_BIN" ]] || die "$PYTHON_BIN not found; run ./scripts/local.sh bootstrap" 2
}

command="${1:-}"
case "$command" in
  -h|--help|help)
    usage
    ;;
  check|list|list-models|inspect|status|verify|plan|download|info|install-upload)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      command_usage "$command"
      exit 0
    fi
    require_models_python
    export ROOT_DIR CONFIG_FILE CATALOG_FILE HF_CLI
    PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}" PYTHONUNBUFFERED=1 \
      exec "$PYTHON_BIN" -m scripts.models.cli "$command" "$@"
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
