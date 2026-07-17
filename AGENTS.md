## comfy-shell 项目边界

本仓库是管理 `ComfyUI` checkout 的壳项目，不是 ComfyUI 上游源码本体。

### scripts 使用边界

`scripts/` 是本仓库稳定操作入口。Agent 需要运行、修改或验证本项目时，优先通过
这些入口理解职责和副作用；完整参数与维护规范以 `scripts/README.md` 和各脚本
`-h` 输出为准，`AGENTS.md` 只记录入口选择边界。

- `scripts/check_env.sh`: 只读环境体检。用于查看仓库、配置、Python/uv、设备、
  端口和基础网络状态；不安装依赖、不下载模型、不启动 ComfyUI。
- `scripts/local.sh`: 本机 ComfyUI runtime 入口。负责 `bootstrap`、`start`、
  `stop`、`restart`、`status`、`logs`；`bootstrap` 是 `.venv` owner，
  `start` 只从已有 `.venv` 启动 ComfyUI。
- `scripts/nodes.sh`: 只管理 ComfyUI-Manager Python 依赖是否可用。它不安装第三方
  `custom_nodes`，不下载模型，不启动 ComfyUI。
- `scripts/models.sh`: 模型 catalog 和本机模型资产入口。用于 `check`、
  `inventory`、`catalog-status`、`verify`、`plan`、显式 `download` 和上传落位；
  不参与 `local.sh bootstrap`，不自动下载模型，不修改 ComfyUI 已跟踪源码。
- `scripts/remote.sh`: 远端 checkout 编排入口。通过 SSH 在远端调用本仓库脚本，
  负责 `sync`、远端 `bootstrap`、生命周期、状态、日志、模型委派、隧道和 GPU
  诊断；会写远端或启动远端进程的命令必须显式确认其副作用。
- `scripts/verify.sh`: scripts 最小可重复验证入口。修改 `scripts/` 后优先按
  `scripts/README.md` 的验证要求运行对应 smoke、help、语法和合同检查。

不要绕过这些入口直接手工改 `.venv`、远端 checkout、模型目录或 ComfyUI 进程状态，
除非当前任务明确要求排查脚本自身无法覆盖的问题。只读命令不得顺手修复环境；安装、
下载、启动、停止和远端写操作都必须由用户意图或当前任务明确覆盖。

### 依赖职责

- 本仓库只有一套 Python 环境: 仓库根目录 `.venv`。
- `.venv` 的 owner 是 `scripts/local.sh bootstrap`。
- `.venv` 同时用于运行 ComfyUI 和执行 `scripts/` 中需要 Python 的辅助脚本。
- 不新增根目录 `pyproject.toml`、`uv.lock`、`requirements.txt` 来管理第二套 scripts 依赖真源。
- `scripts/local.sh bootstrap` 是本机或远端 ComfyUI runtime 部署入口，负责创建 `.venv` 并安装:
  - PyTorch / torchvision / torchaudio
  - `ComfyUI/requirements.txt`
  - `ComfyUI/manager_requirements.txt`
- `scripts/remote.sh` 通过 SSH 在远端 checkout 内调用 `scripts/local.sh`，因此 `local.sh` 不能依赖第二套壳项目依赖同步流程。
- `scripts/models.sh` 可以拆 Python 子模块，但必须复用同一个 `.venv/bin/python`。缺少 `PyYAML` 等依赖时，应提示用户先执行 `./scripts/local.sh bootstrap`，不要自动创建或同步另一套环境。
- `scripts/lib/models_cli.py` 是 `scripts/models.sh` 的实现细节，不是新的用户入口；文档和示例仍应只暴露 `./scripts/models.sh ...`。

### Python 与 uv

- `uv` 是 `.venv` 的安装工具，不是本仓库的根项目依赖管理体系。
- `scripts/local.sh bootstrap` 可以使用 `uv venv` 和 `uv pip install` 安装 ComfyUI runtime。
- 不在 `scripts/local.sh bootstrap` 中执行根项目 `uv sync`。
- `.env` / `.env.example` 中的 `COMFY_PYTHON` 是 ComfyUI runtime 部署配置。
- 国内 PyPI 镜像通过命令环境变量 `UV_INDEX_URL` 临时覆盖，不通过根项目配置文件制造第二套入口。

### 修改脚本时

- 不要把壳脚本依赖和 ComfyUI runtime 依赖混为一谈。
- Shell 入口负责用户合同、help 和环境边界；Python 子模块负责复杂解析、结构化数据、hash、下载计划等实现细节。
- 如果新增 `scripts/` 里的 Python helper，优先使用 Python 标准库或 `.venv` 中已由 ComfyUI runtime 提供的依赖。
- 如果确实需要新增第三方 Python 包，优先判断它是否应安装进同一个 `.venv`，并在对应脚本中给出明确错误提示；不要新增第二套环境或第二套依赖真源。
- 如果新增 ComfyUI runtime 依赖，应优先确认它是否属于上游 ComfyUI、Manager、custom node 或模型资产，不要放到根目录依赖文件。
