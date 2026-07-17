# 模型命令速查

这份速查表只解决一件事：用 `models.sh` 和 `remote.sh models` 检查、下载、验证本机或远端 ComfyUI 模型。

## 先记住边界

```text
本机模型操作
  -> ./scripts/models.sh ...
  -> 读取本机 checkout 的 .env
  -> 使用本机 COMFY_MODEL_ROOT

远端模型操作
  -> ./scripts/remote.sh models ...
  -> 本机 .env 只负责 REMOTE_HOST / REMOTE_DIR
  -> 远端 checkout 的 .env 负责远端 COMFY_MODEL_ROOT
  -> 实际执行的是远端 ./scripts/models.sh ...
```

`.env.example` 是本机配置模板；`.env.remote.example` 是远端 checkout 的 `.env` 复制模板。
默认运行配置真源始终是当前机器 checkout 根目录的 `.env`。

## 状态怎么读

| 状态 | 含义 | 下一步 |
|---|---|---|
| `OK` | 文件存在且 hash 正确 | 不需要处理 |
| `Missing` | 文件缺失，但 catalog 已有可信自动下载信息 | 执行 `download <bundle>` |
| `Manual` | 文件缺失，脚本不应自动下载 | 按 source page 或教程说明手动下载到 target |
| `Blocked` | catalog 信息不足或策略阻塞 | 补齐可信 `sha256` / 来源后再下载 |
| `Present Unverified` | 文件存在，但 catalog 没有 hash 可校验 | 补 hash 或接受不可复现风险 |
| `Bad` | 文件存在但 hash、大小或内容不符合 catalog | 人工检查后替换正确文件 |
| `Conflict` | 多个 bundle 对同一 target 的声明互相冲突 | 修正 `configs/models/catalog.yaml` |

## 本机常用命令

前提：本机 `.env` 已配置真实模型目录。

```dotenv
COMFY_MODEL_ROOT=./ComfyUI/models
```

如果 `models.sh check` 提示缺 `PyYAML` 或 `.venv/bin/python`，先按根 [README](../../README.md) 完成 `.env` 初始化，再执行：

```bash
./scripts/local.sh bootstrap
```

日常检查：

```bash
./scripts/models.sh check
./scripts/models.sh list
./scripts/models.sh list-models retro-anime-photo-core
./scripts/models.sh status retro-anime-photo-core
./scripts/models.sh status --model isabelia-v10-checkpoint
./scripts/models.sh plan retro-anime-photo-core
./scripts/models.sh plan --model isabelia-v10-checkpoint
```

下载支持自动下载的模型：

```bash
./scripts/models.sh download retro-anime-photo-core
./scripts/models.sh download --model isabelia-v10-checkpoint
./scripts/models.sh status retro-anime-photo-core
./scripts/models.sh verify retro-anime-photo-core
./scripts/models.sh verify --model isabelia-v10-checkpoint
```

Hugging Face 下载慢时，可以只对本次命令指定镜像：

```bash
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download retro-anime-photo-core
```

`HF_ENDPOINT` 只影响 `download.method=huggingface`，不影响 Civitai。

## 远端常用命令

前提一：本机 `.env` 已配置远端 checkout。

```dotenv
REMOTE_HOST=wangqiao@47.94.108.140
REMOTE_DIR=/data/wangqiao/comfy-shell
```

前提二：远端 checkout 的 `.env` 已配置远端 ComfyUI 模型目录。

```dotenv
COMFY_MODEL_ROOT=/data/wangqiao/ComfyUI/models
```

可以在同步后把远端模板复制成远端 `.env`：

```bash
ssh wangqiao@47.94.108.140 'cd /data/wangqiao/comfy-shell && cp .env.remote.example .env'
```

前提三：远端已执行过 `bootstrap`，或者远端 checkout 的 `.venv/bin/python` 已可 import `PyYAML`。

先把最新脚本和 catalog 同步到远端：

```bash
./scripts/remote.sh sync --yes
```

如果远端还没有准备过运行环境，先执行：

```bash
./scripts/remote.sh bootstrap --yes
```

远端检查和预览：

```bash
./scripts/remote.sh models check
./scripts/remote.sh models list-models retro-anime-photo-core
./scripts/remote.sh models status retro-anime-photo-core
./scripts/remote.sh models status --model isabelia-v10-checkpoint
./scripts/remote.sh models plan retro-anime-photo-core
./scripts/remote.sh models plan --model isabelia-v10-checkpoint
```

远端后台下载大模型，避免本地终端关闭导致中断：

```bash
./scripts/remote.sh models download retro-anime-photo-core --detach
./scripts/remote.sh models download --model isabelia-v10-checkpoint --detach
./scripts/remote.sh models logs retro-anime-photo-core --follow
./scripts/remote.sh models logs --model isabelia-v10-checkpoint --follow
```

下载后复查：

```bash
./scripts/remote.sh models status retro-anime-photo-core
./scripts/remote.sh models verify retro-anime-photo-core
```

如果远端提示 `Missing`，但 `download` 没有继续下载，先看日志里的 `failed` 原因；如果提示 `Manual`，说明脚本刻意跳过，需要手动确认来源。

## 本地下载再上传远端

当远端访问某个模型源失败，例如 Civitai 返回网络不可达，可以只处理缺失的 model id。

先在远端确认缺哪个模型：

```bash
./scripts/remote.sh models status retro-anime-photo-core
```

本机下载指定模型：

```bash
./scripts/models.sh download --model isabelia-v10-checkpoint
./scripts/models.sh verify --model isabelia-v10-checkpoint
```

上传到远端：

```bash
./scripts/remote.sh models upload --model isabelia-v10-checkpoint
./scripts/remote.sh models verify --model isabelia-v10-checkpoint
```

`upload --model` 会先校验本机文件，再上传到远端临时文件，最后由远端 `models.sh` 校验 hash 后移动到 target。远端 target 已存在且校验通过时会跳过；远端 target 已存在但校验失败时会拒绝覆盖。

上传未登记到 catalog 的本机单个模型文件：

```bash
./scripts/remote.sh models upload-file --file ./ComfyUI/models/vae/vaeKlF8Anime2_klF8Anime2VAE.safetensors --to vae
./scripts/remote.sh models upload-file --file ./ComfyUI/models/upscale_models/4xUltrasharp_4xUltrasharpV10.pt --to upscale_models
./scripts/remote.sh models upload-file --file  ./ComfyUI/models/checkpoints/isabelia_v10.safetensors --to checkpoints --name isabelia_v10.safetensors
```

`upload-file` 不读取 `catalog.yaml`，只负责把本机文件同步到远端 `COMFY_MODEL_ROOT/<to>/<name>`。它会先上传到远端临时文件，再校验 `size/sha256`；远端 target 已存在且内容相同会跳过，内容不同会拒绝覆盖。

## Manual 模型怎么补

`Manual` 不是脚本坏了，而是 catalog 没有足够信息保证自动下载一定拿到正确文件。

处理方式：

1. 打开输出里的 `source page`，或查看 workflow 作者说明。
2. 确认文件确实是 workflow 需要的模型。
3. 下载到输出里的 `target` 路径。
4. 文件名必须和 `target` 一致。
5. 重新执行 `status` 或 `verify`。

不要把名字相近的模型直接改名成目标文件，除非已经确认它们是同一个模型版本。

## catalog 改完后

本机先校验：

```bash
./scripts/models.sh check
./scripts/models.sh status retro-anime-photo-core
```

远端使用前先同步：

```bash
./scripts/remote.sh sync --yes
./scripts/remote.sh models check
./scripts/remote.sh models status retro-anime-photo-core
```
