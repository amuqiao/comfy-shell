# 模型管理

模型管理的目标是让 ComfyUI 能稳定找到模型，并让 Mac 本机和服务器以后能复用同一套目录规则。

## 基本原则

不要把所有模型都放进一个目录。按模型类型放置：

```text
ComfyUI/models/checkpoints/        SDXL、Flux FP8 单文件 checkpoint
ComfyUI/models/diffusion_models/   Flux full、Wan 视频模型
ComfyUI/models/text_encoders/      t5xxl、umt5 等文本编码器
ComfyUI/models/vae/                VAE
ComfyUI/models/clip_vision/        图生视频/参考图相关视觉编码器
ComfyUI/models/loras/              LoRA 风格包
ComfyUI/models/controlnet/         ControlNet / Canny / Depth
ComfyUI/models/upscale_models/     放大模型
```

工作流报 missing model 时，先看节点名称和模型类型，再检查目录。

## 入门阶段怎么放

Mac 本机先用默认目录：

```text
ComfyUI/models/
```

不要太早抽象外部模型仓库。先跑通文生图、图生图、图生视频，再整理。

## 服务器阶段怎么放

服务器磁盘更适合放大模型。建议统一放到数据盘：

```text
/data/wangqiao/ComfyUI/models/
```

不要放到系统盘或用户家目录。视频模型和 Flux/Wan 类模型很容易占几十 GB。

## 模型命名建议

保留来源和精度信息，避免以后分不清：

```text
sdxl-base-1.0.safetensors
flux-schnell-fp8.safetensors
wan2.1-i2v-480p-fp8.safetensors
t5xxl-fp16.safetensors
vae-ft-mse.safetensors
```

不要使用：

```text
model.safetensors
new.safetensors
test1.safetensors
```

## 下载后检查

每次下载模型后先检查：

```bash
ls -lh ComfyUI/models/checkpoints
ls -lh ComfyUI/models/diffusion_models
ls -lh ComfyUI/models/vae
```

如果模型列表不刷新，重启服务：

```bash
./scripts/dev.sh restart
./scripts/dev.sh status
```

## 页面下载模型

新手优先用 ComfyUI 页面管理模型：

1. 打开 ComfyUI。
2. 导入教程里的 workflow 或蓝图。
3. 如果页面提示缺少模型，先看节点提示的模型名和目录。
4. 通过 ComfyUI-Manager 或工作流里的模型提示下载。
5. 下载完成后重启 ComfyUI，刷新模型列表。

这种方式适合探索和补缺。缺点是模型来源、文件名、用途和服务器复现路径不够集中，所以常用模型应逐步沉淀到 `configs/models/catalog.yaml`。

## 可选：用 models.sh 管理标准模型包

本项目提供可选脚本：

```text
configs/models/catalog.yaml
scripts/models.sh
```

它不替代页面操作，只负责把教程中的基础模型包标准化，方便以后在 Mac 和服务器复现。

常用命令：

```bash
./scripts/models.sh list
./scripts/models.sh status
./scripts/models.sh plan sdxl-basic
./scripts/models.sh status sdxl-basic
```

显式下载模型：

```bash
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download sdxl-basic
```

视频模型较大，先看计划和磁盘空间：

```bash
./scripts/models.sh plan wan22-i2v-basic
./scripts/models.sh plan wan22-t2v-basic
df -h ComfyUI/models
```

`models.sh` 的边界：

```text
list/status/plan   只读，不访问网络
  download           显式下载，写入 ComfyUI/models 下的模型资产目录
```

它不会被 `dev.sh bootstrap` 自动调用，也不会静默下载大文件。

## 什么时候使用 extra_model_paths.yaml

当模型变多，或你希望 Mac 和服务器共用同一套模型仓库时，再使用 `extra_model_paths.yaml`。

适合的结构：

```text
/data/models/comfy/
  checkpoints/
  diffusion_models/
  text_encoders/
  vae/
  loras/
  controlnet/
  upscale_models/
```

然后让 ComfyUI 通过 `extra_model_paths.yaml` 读取这个外部目录。

入门阶段可以暂时不做这一步，避免把学习重点从作品转移到目录配置。

## 与本项目脚本的关系

当前 `comfy-shell` 脚本负责：

```text
环境 profile
.venv 依赖
ComfyUI-Manager Python 包
启动 / 停止 / 状态
```

当前脚本不负责：

```text
自动下载模型
自动安装第三方 custom_nodes
自动迁移模型目录
```

模型下载和放置由你显式执行。`models.sh download` 是可选的显式下载入口，不会被启动或安装脚本自动触发；它只写模型资产目录，不修改 ComfyUI 已跟踪源码文件。

## 推荐习惯

- 下载一个模型后，立即记录它用于哪个 workflow。
- 每个作品保存 workflow JSON。
- 不常用的大模型先移到归档目录，不要长期堆在默认目录。
- 服务器上定期检查磁盘空间。
