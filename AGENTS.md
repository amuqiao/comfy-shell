## comfy-shell 项目边界

本仓库是管理 `ComfyUI` checkout 的壳项目，不是 ComfyUI 上游源码本体。

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
