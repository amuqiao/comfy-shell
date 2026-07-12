# 模型管理

模型管理的目标是让 ComfyUI 能稳定找到模型，并让 Mac 本机和服务器以后能复用同一套目录规则。

## 基本原则

不要把所有模型都放进一个目录。按模型类型放置：

```text
ComfyUI/models/checkpoints/        单文件 checkpoint
ComfyUI/models/diffusion_models/   Flux full、Wan 视频模型
ComfyUI/models/text_encoders/      t5xxl、umt5 等文本编码器
ComfyUI/models/vae/                VAE
ComfyUI/models/clip_vision/        参考图相关视觉编码器
ComfyUI/models/loras/              LoRA 风格包或角色包
ComfyUI/models/controlnet/         ControlNet / Canny / Depth
ComfyUI/models/upscale_models/     放大模型
```

工作流报 missing model 时，先看节点名称和模型类型，再检查目录。

## 业务阶段怎么放

当前项目不再按“基础教程”组织模型，而是按 AI 女主内容生产线组织。

已落地到 `configs/models/catalog.yaml`、可用 `models.sh` 管理的模型包：

```text
heroine-i2v-core         图生视频主线
heroine-t2v-explore      文生视频探索，不作为主生产路径
```

规划中、暂未标准化到 catalog 的模型包：

```text
heroine-image-core       女主身份图、封面、首帧
heroine-image-edit       变装、试穿、局部编辑
```

Mac 本机可以先用默认目录：

```text
ComfyUI/models/
```

视频模型和图像主力模型都很大。不要为了省下载成本选择过时模型；真正要节省的是重复下载、目录混乱和模型用途不清。

## 服务器阶段怎么放

服务器磁盘更适合放大模型。建议统一放到数据盘：

```text
/data/wangqiao/ComfyUI/models/
```

不要放到系统盘或用户家目录。视频模型和 Flux/Wan 类模型很容易占几十 GB。

## 模型命名建议

保留来源、用途和精度信息，避免以后分不清：

```text
wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors
wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors
umt5_xxl_fp8_e4m3fn_scaled.safetensors
heroine-v1-lora.safetensors
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
ls -lh ComfyUI/models/text_encoders
ls -lh ComfyUI/models/vae
```

如果模型列表不刷新，重启服务：

```bash
./scripts/dev.sh restart
./scripts/dev.sh status
```

## 页面下载模型

页面下载适合探索和补缺：

1. 打开 ComfyUI。
2. 导入业务 workflow 或自带蓝图。
3. 如果页面提示缺少模型，先看节点提示的模型名和目录。
4. 通过 ComfyUI-Manager 或 workflow 的模型提示下载。
5. 下载完成后重启 ComfyUI，刷新模型列表。

常用模型最后应沉淀到 `configs/models/catalog.yaml`，否则 Mac 和服务器很难复现。

## 可选：用 models.sh 管理生产线模型包

本项目提供可选脚本：

```text
configs/models/catalog.yaml
scripts/models.sh
```

它不替代页面操作，只负责把生产线常用模型包标准化，方便以后在 Mac 和服务器复现。

常用命令：

```bash
./scripts/models.sh list
./scripts/models.sh status
./scripts/models.sh plan heroine-i2v-core
./scripts/models.sh status heroine-i2v-core
```

显式下载模型：

```bash
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core
```

视频模型较大，先看计划和磁盘空间：

```bash
./scripts/models.sh plan heroine-i2v-core
./scripts/models.sh plan heroine-t2v-explore
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

本机实践阶段可以暂时不做这一步，避免把重点从作品转移到目录配置。

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

- 下载一个模型后，立即记录它用于哪个业务 workflow。
- 每个作品保存 workflow JSON。
- 女主身份、变装关键帧、视频首帧要放进 `assets/heroine/`，不要只留在 `ComfyUI/output/`。
- 不常用的大模型先移到归档目录，不要长期堆在默认目录。
- 服务器上定期检查磁盘空间。
