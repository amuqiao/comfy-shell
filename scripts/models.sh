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
  ./scripts/models.sh list
  ./scripts/models.sh inspect <workflow.png|workflow.json>
  ./scripts/models.sh status [bundle] [--profile FILE]
  ./scripts/models.sh verify [bundle] [--profile FILE]
  ./scripts/models.sh plan <bundle> [--profile FILE]
  ./scripts/models.sh download <bundle> [--profile FILE]
  ./scripts/models.sh -h|--help

作用域:
  可选的 ComfyUI 模型资产入口。读取 configs/models/catalog.yaml, 列出教程模型包,
  检查本地文件, 校验 hash, 预览下载计划, 并在用户显式执行时调用 Hugging Face CLI 下载。

不负责:
  不参与 local.sh bootstrap, 不自动下载模型, 不删除模型文件, 不安装 third-party custom_nodes,
  不修改 ComfyUI 已跟踪源码文件。

运行环境:
  Requires: Bash, 仓库根目录 .venv/bin/python
  list/status/verify/plan/download 需要 .venv 中可 import PyYAML。
  inspect 只解析 PNG/JSON workflow metadata, 不访问网络, 不猜下载源。
  download 需要 hf CLI; 优先使用 .venv/bin/hf, 其次使用 HF_CLI 或 PATH 中的 hf。
  source=manual 的条目只在 status/plan 中展示, 不会自动下载。
  下载文件名必须和 catalog filename 一致; 不自动把相似文件重命名成 workflow 文件名。
  source=huggingface 的条目缺少 sha256 时会标记 BLOCKED, 不自动下载。

命令:
  list                列出 catalog 中的 bundle
  inspect <file>      从 PNG/workflow JSON 提取模型引用
  status [bundle]     检查 bundle 模型文件是否存在、是否可验证
  verify [bundle]     要求 bundle 模型文件存在且 hash 正确
  plan <bundle>       输出下载目标路径和 hf download 命令
  download <bundle>   显式下载 bundle 中的模型文件
  help                显示本帮助

配置与环境变量:
  默认读取仓库根目录 .env。
  --profile FILE      status/verify/plan/download 可显式指定其他配置文件。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。
  HF_ENDPOINT         可选; 进程环境变量优先, 其次读取配置文件。示例: https://hf-mirror.com
  CATALOG_FILE        可选, 覆盖 catalog 路径
  PYTHON_BIN          可选, 覆盖 Python 路径
  HF_CLI              可选, 覆盖 hf CLI 路径

副作用与保护边界:
  list/inspect/status/verify/plan 只读, 不访问网络。
  download 会创建模型子目录并写 Hugging Face 模型文件; 写入 COMFY_MODEL_ROOT 下的模型资产目录。
  source=manual 的条目会输出 MANUAL 提示, 需要用户自行下载。
  缺 sha256、hash 不匹配或已有文件 hash 错误时, download 直接失败或跳过, 不覆盖。
  download 必须由用户显式执行, 不修改 ComfyUI 已跟踪源码文件。
  所有相对模型路径按仓库根目录解析。

常用示例:
  ./scripts/models.sh list
  ./scripts/models.sh inspect '.data/nodes/批量照片转绘复古动漫风格（LoRA+ControlNet+UltimateSDUpscale）.png'
  ./scripts/models.sh plan retro-anime-photo-core --profile .env.example
  ./scripts/models.sh plan heroine-i2v-core --profile .env.example
  ./scripts/models.sh status retro-anime-photo-core --profile .env.example
  HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core

Exit Codes:
  0  成功
  1  status/verify 检查发现模型文件缺失、manual、blocked 或 hash 不匹配
  2  缺少 command、非法参数、catalog 缺失、Python/PyYAML/hf 缺失
  4  下载运行失败
EOF
}

command_usage() {
  local name="$1"
  case "$name" in
    list)
      cat <<'EOF'
用法:
  ./scripts/models.sh list
  ./scripts/models.sh list -h|--help

作用域:
  列出 catalog 中的 bundle。list 不读取配置文件。
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
  ./scripts/models.sh status [bundle] [--profile FILE]
  ./scripts/models.sh status -h|--help

作用域:
  检查 bundle 模型文件是否存在且非空。
  有 sha256 时会校验 hash; 缺少 sha256 的自动下载条目标记 BLOCKED。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。

常用示例:
  ./scripts/models.sh status
  ./scripts/models.sh status heroine-i2v-core
  ./scripts/models.sh status --profile .env.example
EOF
      ;;
    verify)
      cat <<'EOF'
用法:
  ./scripts/models.sh verify [bundle] [--profile FILE]
  ./scripts/models.sh verify -h|--help

作用域:
  严格校验 bundle 模型文件。只有文件存在且 sha256 正确才算 OK。
  source=manual 或缺少 sha256 的条目会返回非 0。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。

常用示例:
  ./scripts/models.sh verify retro-anime-photo-core
  ./scripts/models.sh verify heroine-i2v-core --profile .env.example
EOF
      ;;
    plan)
      cat <<'EOF'
用法:
  ./scripts/models.sh plan <bundle> [--profile FILE]
  ./scripts/models.sh plan -h|--help

作用域:
  输出下载目标路径和 hf download 命令, 不访问网络。
  source=manual 或缺少 sha256 的条目会明确显示 MANUAL/BLOCKED。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。

常用示例:
  ./scripts/models.sh plan heroine-i2v-core
  ./scripts/models.sh plan heroine-i2v-core --profile .env.example
EOF
      ;;
    download)
      cat <<'EOF'
用法:
  ./scripts/models.sh download <bundle> [--profile FILE]
  ./scripts/models.sh download -h|--help

作用域:
  显式下载 bundle 中的模型文件。

配置:
  默认读取 .env; --profile FILE 可显式指定其他配置文件。
  COMFY_MODEL_ROOT    进程环境变量优先, 其次读取配置文件。
  HF_ENDPOINT         可选; 进程环境变量优先, 其次读取配置文件。

常用示例:
  HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core
  ./scripts/models.sh download heroine-i2v-core --profile .env.example
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
  list|inspect|status|verify|plan|download)
    shift
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      command_usage "$command"
      exit 0
    fi
    require_models_python
    export ROOT_DIR CONFIG_FILE CATALOG_FILE HF_CLI
    exec "$PYTHON_BIN" "$ROOT_DIR/scripts/lib/models_cli.py" "$command" "$@"
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
