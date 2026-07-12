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

模型下载和放置由你显式执行。这样可以避免脚本静默下载大文件，也更容易控制磁盘空间。

## 推荐习惯

- 下载一个模型后，立即记录它用于哪个 workflow。
- 每个作品保存 workflow JSON。
- 不常用的大模型先移到归档目录，不要长期堆在默认目录。
- 服务器上定期检查磁盘空间。

