# scripts 维护规范

本文说明 `scripts/` 下本地入口脚本的职责边界和帮助文档规则。具体参数以各脚本自身 `-h` 输出为准，本文不复制完整命令手册。

## 工作模型

`scripts/` 是 `comfy-shell` 的稳定操作入口。壳项目只管理 ComfyUI 外层运行流程，不把 ComfyUI 上游源码、模型文件或第三方节点代码混进主仓库。

```text
check_env.sh            只读环境体检
local.sh                  本机 ComfyUI 环境准备和进程生命周期
nodes.sh                ComfyUI-Manager 依赖状态和安装
models.sh               当前机器模型 catalog 校验、清单查看、模型校验和显式下载
remote.sh               远端项目 checkout 编排、远端模型委派、隧道和 GPU 诊断
verify.sh               scripts 最小可重复校验
```

当前阶段不提供 Docker 或第三方 custom nodes 管理入口。新增能力前，先判断它是否属于已有入口的子命令；只有职责边界不同、生命周期不同或安全边界不同，才新增顶层 `*.sh`。
一次性脚手架和迁移工具放在 `tools/`，不算 `scripts/` 稳定操作入口。

## 入口职责

Shell 入口默认只负责：

- 定位仓库根目录和运行时路径。
- 读取仓库根目录 `.env` 中的白名单配置键；显式 `--profile FILE` 只用于单次指定其他配置文件。
- 做轻量参数分发。
- 提供稳定、可读、可复制的 help。
- 调用 `uv`、Python 或 ComfyUI 入口完成明确动作。

不要在脚本中 `source .env`、`eval` 配置文件内容，或透传自由 shell 片段。配置文件是数据，不是脚本。

## Help 分层

顶层 help 应回答：

- 这个入口负责什么。
- 不负责什么。
- 有哪些命令。
- 读取哪些环境变量。
- stdout / stderr 输出什么。
- 会产生哪些副作用。
- 用户最常复制的命令。
- 退出码含义。

子命令 help 应回答：

- 这个动作会做什么。
- 是否会安装依赖、写文件、启动或停止进程、访问网络。
- 需要哪些前置条件。
- 可直接粘贴的示例。

## 配置边界

仓库根目录 `.env` 是默认配置真源。脚本默认读取 `.env`，但不 `source` 或执行其中内容。
`.env.example` 只是 `cp .env.example .env` 的模板，不作为运行 profile 示例。
如需临时读取其他配置文件，必须在命令中显式写 `--profile FILE`；这只覆盖本次命令，不改变默认真源。`.env` 不提交。

配置读取规则：

```text
脚本显式支持的 CLI 参数
> 进程环境变量
> .env 或显式 --profile FILE 中的白名单配置键
```

不要把任意配置键都当作自由 shell 片段执行。只允许脚本白名单读取的键生效。
同名进程环境变量优先于配置文件值，适合临时覆盖。

常见配置：

```text
COMFY_PROFILE          当前配置名
COMFY_ENV_BACKEND      当前阶段只支持 uv
COMFY_PYTHON           uv 创建 .venv 使用的 Python 版本
COMFY_DEVICE           mps / cuda / cpu
COMFY_HOST             本机开发阶段只允许 127.0.0.1 / localhost / ::1
COMFY_PORT             ComfyUI 监听端口
TORCH_PRE              true 时安装 PyTorch 使用 --pre
TORCH_INDEX_URL        PyTorch 专用 wheel 源
UV_INDEX_URL           uv 默认 Python 包索引，可在命令前临时设置
REMOTE_HOST            remote.sh 默认 SSH 目标, 例如 wangqiao@47.94.108.140
REMOTE_DIR             remote.sh 默认远端 checkout 绝对路径
REMOTE_READY_URL       remote.sh ready 默认检查的远端本机 URL
REMOTE_TUNNEL_*        remote.sh tunnel 默认本地/远端 host/端口
REMOTE_LOG_TAIL        remote.sh logs 默认 tail 行数
REMOTE_GPU_CONNECT_TIMEOUT remote.sh gpu 默认 SSH ConnectTimeout
```

`TORCH_INDEX_URL` 只用于 `torch` / `torchvision` / `torchaudio` 安装。`UV_INDEX_URL` 是 `uv` 自身读取的环境变量，影响普通 Python 依赖，例如 ComfyUI requirements 和 Manager 依赖。

帮助文档里的源配置示例按这个规则写：

- `UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple ./scripts/local.sh bootstrap`
  可以作为命令前缀示例，因为它由 `uv` 自己读取。
- `TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124 ./scripts/local.sh bootstrap`
  可以作为一次性覆盖示例，因为脚本实现会优先读取同名进程环境变量。

## 副作用边界

- `check_env.sh` 只读，不安装、不下载、不启动；默认读取 `.env`。
- `local.sh bootstrap` 会创建或复用 `.venv`，创建 `.run/` 和 `logs/`，并安装 Python 依赖。
- `local.sh start` 会启动本机后台 ComfyUI，写 `.run/comfyui.pid` 和 `logs/comfyui.log`。
- `local.sh stop` 只停止 pid 文件指向且命令行匹配 ComfyUI 的进程。
- `nodes.sh install manager` 会安装 `ComfyUI/manager_requirements.txt` 到 `.venv`。
- `remote.sh sync/bootstrap/start/stop/restart` 会通过 SSH/rsync 修改远端 checkout
  或远端 ComfyUI 进程；默认目标来自 `.env` 的 `REMOTE_HOST` / `REMOTE_DIR`。
  `remote.sh status/ready/logs` 只读查看远端状态。
- `remote.sh models [options] <check|list|status|verify|plan|download|logs>` 会通过 SSH
  进入远端 checkout 并调用远端 `./scripts/models.sh ...`。其中 `download` 会在
  远端 `COMFY_MODEL_ROOT` 写模型文件；模型清单、hash 和目标目录仍由远端
  `models.sh` 负责。`download --detach` 会在远端后台运行, 写
  `.run/models-download-<bundle>.pid` 和 `logs/models-download-<bundle>.log`。
  这里的 `--profile` 只用于本机 `remote.sh` 定位远端，不会传给远端
  `models.sh`；远端模型配置读取远端 checkout 根目录 `.env`。

远端大模型下载建议路径：

```bash
./scripts/remote.sh models check
./scripts/remote.sh models plan retro-anime-photo-core
./scripts/remote.sh models download retro-anime-photo-core --detach
./scripts/remote.sh models logs retro-anime-photo-core --follow
./scripts/remote.sh models verify retro-anime-photo-core
```
- `remote.sh gpu` 只读查询远端 `nvidia-smi`，不会管理进程或文件。
- `remote.sh tunnel` 会在当前终端打开 SSH 本地端口转发，不启动远程服务，不写文件。

安装、下载、启动都必须由用户显式执行对应命令；不要在只读命令里顺手修复环境。
`local.sh start` 默认启用上游 ComfyUI-Manager；壳脚本本身不会在启动时执行
`pip` 安装、模型下载或第三方 `custom_nodes` 安装，但 Manager 可能执行自己的
安全检查或处理此前从 UI 排队的任务。相关提示必须写进 `local.sh -h` 和运行输出。

## 验证要求

修改 `scripts/` 后至少运行：

```bash
bash -n scripts/*.sh
./scripts/check_env.sh -h
./scripts/local.sh -h
./scripts/nodes.sh -h
./scripts/models.sh check
./scripts/models.sh -h
./scripts/remote.sh -h
./scripts/verify.sh -h
./scripts/verify.sh check
git diff --check
```

修改 `local.sh` 的启动、停止、PID 或端口逻辑后，还需要用户显式执行真实启动验证：

```bash
./scripts/local.sh start
./scripts/local.sh status
./scripts/local.sh stop
```

## 新增脚本 Checklist

- 职责是否不能放入已有入口。
- 文件名是否稳定、可预测，并使用 `.sh`。
- `-h` 是否说明作用域、不负责什么、命令、配置、输出、副作用、示例和退出码。
- 是否避免 silent fallback；配置错误应快速失败。
- 是否默认读取 `.env`，且只有显式 `--profile FILE` 时才读取其他配置文件。
- 是否避免执行 `.env` 或其他配置文件内容。
- 是否明确哪些命令会访问网络、安装依赖、写文件或启动进程。
- 是否完成最小验证。
