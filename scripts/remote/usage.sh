#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/remote/usage.sh must be sourced, not executed directly\n' >&2
  exit 2
fi

usage() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh sync --yes [options]
  ./scripts/remote.sh bootstrap --yes [options]
  ./scripts/remote.sh start --yes [options]
  ./scripts/remote.sh stop --yes [options]
  ./scripts/remote.sh restart --yes [options]
  ./scripts/remote.sh status [options]
  ./scripts/remote.sh logs [--tail N|all] [--follow] [options]
  ./scripts/remote.sh models [options] <check|list|list-models|inventory|catalog-status|status|verify|plan|download|upload|upload-file|logs> [...]
  ./scripts/remote.sh ready [--url URL] [options]
  ./scripts/remote.sh tunnel [--local-port PORT] [--remote-host HOST] [--remote-port PORT] [--dry-run] [options]
  ./scripts/remote.sh gpu [--connect-timeout SECONDS] [--json] [options]
  ./scripts/remote.sh -h|--help
  ./scripts/remote.sh <command> -h|--help

作用域:
  唯一远端入口。负责从本机通过 SSH/rsync 编排远端 comfy-shell checkout:
  同步代码、执行远端 checkout 内的 local.sh 生命周期、查看日志、健康检查、SSH 隧道和 GPU 只读诊断。
  远端模型操作由 remote.sh models 委派给远端 checkout 内的 models.sh。

不负责:
  不管理 Docker、systemd、第三方 custom_nodes、模型来源判断或公网端口暴露。
  不读取远端 secret, 不执行自由 shell 片段, 不提供兼容 wrapper。

配置与环境变量:
  无 --host/--dir 的命令读取仓库根目录 .env 中的真实远端目标:
    REMOTE_HOST=wangqiao@47.94.108.140
    REMOTE_DIR=/data/wangqiao/comfy-shell
  默认读取仓库根目录 .env 的 REMOTE_* 键; 已导出的同名环境变量优先。
  CLI 参数只覆盖本次调用: --profile、--host、--dir、--url、--local-port、--remote-port。
  --profile FILE 指定本机 remote.sh 本次读取的配置文件。
  远端 local.sh 默认读取远端 checkout 根目录 .env。
  远端 models.sh 默认读取远端 checkout 根目录 .env; remote.sh models 不透传 models.sh --profile。

副作用与保护边界:
  sync/bootstrap/start/stop/restart 必须显式传 --yes。
  sync --yes 会创建远端目录并上传本地 checkout; --delete 会删除远端多余的非排除文件。
  bootstrap --yes 会在远端写 .venv、.run/、logs/ 并访问 Python 包索引。
  start/stop/restart --yes 会在远端启动或停止 ComfyUI 进程。
  models download/upload 会在远端 COMFY_MODEL_ROOT 写模型文件; --detach 会写 .run/ 和 logs/。
  status/logs/ready/gpu 和 models check/list/inventory/catalog-status/verify/plan/logs 只读; tunnel 只占用本地端口并保持 SSH 前台进程。

输出:
  stdout 输出命令、远端脚本结果、日志、健康检查 HTTP code、隧道命令或 GPU 状态。
  gpu --json 时 stdout 只输出单个 JSON 文档。
  stderr 输出参数错误、缺少依赖、ssh/rsync/curl/nvidia-smi 诊断。

常用示例:
  # 首次或 .env 缺 REMOTE_* 时, 先把 .env.example 中的 REMOTE_* 合并到 .env。
  ./scripts/remote.sh sync --yes
  ./scripts/remote.sh bootstrap --yes
  ./scripts/remote.sh start --yes
  ./scripts/remote.sh restart --yes
  ./scripts/remote.sh stop --yes
  ./scripts/remote.sh status
  ./scripts/remote.sh models check
  ./scripts/remote.sh models list-models retro-anime-photo-core
  ./scripts/remote.sh models plan retro-anime-photo-core
  ./scripts/remote.sh models catalog-status --model isabelia-v10-checkpoint
  ./scripts/remote.sh models download retro-anime-photo-core --detach
  ./scripts/remote.sh models upload --model isabelia-v10-checkpoint
  ./scripts/remote.sh models logs retro-anime-photo-core --follow
  ./scripts/remote.sh logs --tail 200
  ./scripts/remote.sh tunnel
  ./scripts/remote.sh gpu

Exit Codes:
  0  成功; ready 返回 HTTP 200。
  1  ready 非 HTTP 200、GPU 概览为空, 或远端 checkout 内的 local.sh 正常执行但业务状态未就绪。
  2  参数、用法、配置或前置条件错误。
  4  入口自身发起运行后的外部依赖、网络、快照格式化或文件产物失败。
  其他非 0 由 ssh、rsync 或远端脚本透传。
EOF
}

usage_sync() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh sync --yes [options]

必需参数:
  --yes                  确认执行写操作。

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  --local-dir DIR        本地 checkout, 默认当前仓库根目录。
  --follow-links         rsync 跟随符号链接。
  --delete               删除远端多余的非排除文件。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

常用示例:
  # 前提: .env 已包含 REMOTE_HOST 和 REMOTE_DIR
  ./scripts/remote.sh sync --yes
EOF
}

usage_bootstrap() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh bootstrap --yes [options]

必需参数:
  --yes                  确认执行写操作。

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  --uv-index-url URL     为远端 local.sh bootstrap 注入 UV_INDEX_URL。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

远端动作:
  cd REMOTE_DIR && ./scripts/local.sh bootstrap

常用示例:
  # 前提: .env 已包含 REMOTE_HOST 和 REMOTE_DIR
  ./scripts/remote.sh bootstrap --yes
EOF
}

usage_lifecycle() {
  local action="${1:-${cmd:-start}}"
  cat <<EOF
用法:
  ./scripts/remote.sh ${action} --yes [options]

必需参数:
  --yes                  确认执行写操作。

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

远端动作:
  cd REMOTE_DIR && ./scripts/local.sh ${action}
EOF
}

usage_status() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh status [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。

远端动作:
  cd REMOTE_DIR && ./scripts/local.sh status
EOF
}

usage_logs() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh logs [--tail N|all] [--follow] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  --tail N|all           输出日志尾部行数或全部日志; 默认 REMOTE_LOG_TAIL, 回退 200。
  --follow               跟随远端 local.sh logs。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST、REMOTE_DIR 和 REMOTE_LOG_TAIL; 已导出环境变量优先。
EOF
}

usage_models() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh models [options] check
  ./scripts/remote.sh models [options] list
  ./scripts/remote.sh models [options] list-models [bundle]
  ./scripts/remote.sh models [options] inventory [--all]
  ./scripts/remote.sh models [options] catalog-status [bundle|--model MODEL_ID]
  ./scripts/remote.sh models [options] status [bundle|--model MODEL_ID]  # compatibility alias
  ./scripts/remote.sh models [options] verify [bundle|--model MODEL_ID]
  ./scripts/remote.sh models [options] plan <bundle|--model MODEL_ID>
  ./scripts/remote.sh models [options] download <bundle|--model MODEL_ID> [--detach]
  ./scripts/remote.sh models [options] upload --model MODEL_ID
  ./scripts/remote.sh models [options] upload-file --file FILE --to MODEL_DIR [--name FILENAME]
  ./scripts/remote.sh models [options] logs <bundle|--model MODEL_ID> [--tail N|all] [--follow]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件, 只用于定位远端。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --dir REMOTE_DIR       覆盖 REMOTE_DIR。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取本机 .env 的 REMOTE_HOST 和 REMOTE_DIR; 已导出环境变量优先。
  远端 models.sh 默认读取远端 checkout 根目录 .env。
  不透传远端 models.sh --profile; 如需改变远端 COMFY_MODEL_ROOT, 修改远端 .env。

远端动作:
  cd REMOTE_DIR && ./scripts/models.sh <check|list|list-models|inventory|catalog-status|verify|plan|download|info|install-upload> [...]

边界:
  remote.sh models 是远端模型操作入口, 只负责 SSH 和远端 checkout 定位。
  模型清单、hash、下载和 COMFY_MODEL_ROOT 由远端 ./scripts/models.sh 负责。
  catalog-status 对账 catalog 声明项; inventory 只扫描远端 COMFY_MODEL_ROOT 实际文件。
  status 是 catalog-status 的兼容别名。
  upload --model 从本机 COMFY_MODEL_ROOT 读取已校验文件, 上传到远端 COMFY_MODEL_ROOT。
  upload-file 不依赖 catalog, 从本机任意 FILE 上传到远端 COMFY_MODEL_ROOT/MODEL_DIR/FILENAME。
  不支持远端 inspect, 也不代理远端 models.sh 子命令帮助。
  workflow 文件解析请在本机使用 ./scripts/models.sh inspect。

副作用:
  check/list/inventory/catalog-status/status/verify/plan/logs 只读。
  download 会在远端 COMFY_MODEL_ROOT 写模型文件, 不启动或停止 ComfyUI。
  download --detach 会在远端后台运行, 写 .run/models-download-<bundle>.pid
  或 .run/models-download-model-<id>.pid, 以及对应 logs/*.log。
  upload --model 会用 rsync 上传本机已校验模型到远端临时文件, 再由远端 models.sh 校验后落位。
  upload-file 会用 rsync 上传本机文件到远端临时文件, 校验 size/sha256 后落位; 远端 target 已存在且内容相同会跳过, 内容不同会拒绝覆盖。

常用示例:
  ./scripts/remote.sh models check
  ./scripts/remote.sh models list
  ./scripts/remote.sh models list-models retro-anime-photo-core
  ./scripts/remote.sh models plan retro-anime-photo-core
  ./scripts/remote.sh models inventory
  ./scripts/remote.sh models inventory --all
  ./scripts/remote.sh models catalog-status --model isabelia-v10-checkpoint
  ./scripts/remote.sh models catalog-status retro-anime-photo-core
  ./scripts/remote.sh models verify retro-anime-photo-core
  ./scripts/remote.sh models download --model isabelia-v10-checkpoint --detach
  ./scripts/remote.sh models download retro-anime-photo-core --detach
  ./scripts/remote.sh models upload --model isabelia-v10-checkpoint
  ./scripts/remote.sh models upload-file --file ./ComfyUI/models/vae/kl-f8-anime2.ckpt --to vae
  ./scripts/remote.sh models upload-file --file ~/Downloads/foo.safetensors --to loras --name foo.safetensors
  ./scripts/remote.sh models logs --model isabelia-v10-checkpoint --follow
  ./scripts/remote.sh models logs retro-anime-photo-core --follow
EOF
}

usage_ready() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh ready [--url URL] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --url URL              远端本机可访问的 ComfyUI base URL。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_READY_URL; 已导出环境变量优先。

远端动作:
  curl URL/system_stats
EOF
}

usage_tunnel() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh tunnel [--local-port PORT] [--remote-host HOST] [--remote-port PORT] [--dry-run] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --local-port PORT      覆盖 REMOTE_TUNNEL_LOCAL_PORT。
  --remote-host HOST     覆盖 REMOTE_TUNNEL_REMOTE_HOST。
  --remote-port PORT     覆盖 REMOTE_TUNNEL_REMOTE_PORT。
  --dry-run              只打印访问 URL、转发关系和 ssh -L 命令, 不建立隧道。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_TUNNEL_*; 已导出环境变量优先。
EOF
}

usage_gpu() {
  cat <<'EOF'
用法:
  ./scripts/remote.sh gpu [--connect-timeout SECONDS] [--json] [options]

选项:
  --profile FILE         本机 remote.sh 本次读取的配置文件。
  --host USER@HOST       覆盖 REMOTE_HOST。
  --connect-timeout N    SSH ConnectTimeout 秒数; 默认 REMOTE_GPU_CONNECT_TIMEOUT, 回退 10。
  --json                 stdout 只输出单个 JSON 文档。
  -h, --help             显示本帮助。

配置与环境变量:
  默认读取 .env 的 REMOTE_HOST 和 REMOTE_GPU_CONNECT_TIMEOUT; 已导出环境变量优先。
EOF
}
