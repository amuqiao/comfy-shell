# scripts 维护规范

本文说明 `scripts/` 下本地入口脚本的职责边界和帮助文档规则。具体参数以各脚本自身 `-h` 输出为准，本文不复制完整命令手册。

## 工作模型

`scripts/` 是 `comfy-shell` 的稳定操作入口。壳项目只管理 ComfyUI 外层运行流程，不把 ComfyUI 上游源码、模型文件或第三方节点代码混进主仓库。

```text
env.sh                  profile 激活与查看
check_env.sh            只读环境体检
local.sh                  本机 ComfyUI 环境准备和进程生命周期
nodes.sh                ComfyUI-Manager 依赖状态和安装
models.sh               可选模型清单查看和显式下载
remote.sh               远端项目 checkout 编排、隧道和 GPU 诊断
verify.sh               scripts 最小可重复校验
create-shell-submodule.sh  壳仓库脚手架
```

当前阶段不提供 Docker 或第三方 custom nodes 管理入口。新增能力前，先判断它是否属于已有入口的子命令；只有职责边界不同、生命周期不同或安全边界不同，才新增顶层 `*.sh`。

## 入口职责

Shell 入口默认只负责：

- 定位仓库根目录和运行时路径。
- 解析 `.env` 中的白名单配置键。
- 做轻量参数分发。
- 提供稳定、可读、可复制的 help。
- 调用 `uv`、Python 或 ComfyUI 入口完成明确动作。

不要在脚本中 `source .env`、`eval` profile 内容，或透传自由 shell 片段。profile 是数据，不是脚本。

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

当前激活 profile 写在仓库根目录 `.env`，由 `./scripts/env.sh use <profile>` 生成。`.env` 不提交。

配置读取规则：

```text
脚本显式支持的 CLI 参数 / 进程环境变量
> .env 中的白名单 profile 键
> 脚本默认值
```

不要把任意 profile 键都假设为可用命令前缀覆盖。比如当前 `local.sh bootstrap`
从 `.env` 读取 `TORCH_INDEX_URL`，不会读取命令前缀里的
`TORCH_INDEX_URL=...`。如果未来需要这种覆盖方式，先改实现，再改 help 示例。

常见配置：

```text
COMFY_PROFILE          当前 profile 名
COMFY_ENV_BACKEND      当前阶段只支持 uv
COMFY_PYTHON           uv 创建 .venv 使用的 Python 版本
COMFY_DEVICE           mps / cuda / cpu
COMFY_HOST             本机开发阶段只允许 127.0.0.1 / localhost / ::1
COMFY_PORT             默认 8188
TORCH_PRE              true 时安装 PyTorch 使用 --pre
TORCH_INDEX_URL        PyTorch 专用 wheel 源
UV_INDEX_URL           uv 默认 Python 包索引，可在命令前临时设置
```

`TORCH_INDEX_URL` 只用于 `torch` / `torchvision` / `torchaudio` 安装。`UV_INDEX_URL` 是 `uv` 自身读取的环境变量，影响普通 Python 依赖，例如 ComfyUI requirements 和 Manager 依赖。

帮助文档里的源配置示例按这个规则写：

- `UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple ./scripts/local.sh bootstrap`
  可以作为命令前缀示例，因为它由 `uv` 自己读取。
- `TORCH_INDEX_URL` 只作为 profile / `.env` 示例展示，不写成命令前缀，除非脚本实现已支持进程环境覆盖。

## 副作用边界

- `env.sh use` 会写 `.env`。
- `check_env.sh` 只读，不安装、不下载、不启动。
- `local.sh bootstrap` 会创建或复用 `.venv`，创建 `.run/` 和 `logs/`，并安装 Python 依赖。
- `local.sh start` 会启动本机后台 ComfyUI，写 `.run/comfyui.pid` 和 `logs/comfyui.log`。
- `local.sh stop` 只停止 pid 文件指向且命令行匹配 ComfyUI 的进程。
- `nodes.sh install manager` 会安装 `ComfyUI/manager_requirements.txt` 到 `.venv`。
- `remote.sh sync/bootstrap/start/stop/restart` 会通过 SSH/rsync 修改远端 checkout
  或远端 ComfyUI 进程；`remote.sh status/ready/logs` 只读查看远端状态。
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
./scripts/env.sh -h
./scripts/check_env.sh -h
./scripts/local.sh -h
./scripts/nodes.sh -h
./scripts/remote.sh -h
./scripts/verify.sh -h
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
- 是否避免执行 `.env` 或 profile 内容。
- 是否明确哪些命令会访问网络、安装依赖、写文件或启动进程。
- 是否完成最小验证。
