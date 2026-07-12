# 模型管理

模型管理的目标是让 ComfyUI 能稳定找到模型，并让 Mac 本机和服务器以后能复用同一套目录规则。

## 当前心智模型

模型按业务环节管理：

```text
女主身份图 / 首帧
变装 / 试穿
图生视频主线
文生视频探索
```

当前只有视频主线模型包已经标准化进 `configs/models/catalog.yaml`。图片生成、图片编辑、试穿模型包还在探索阶段，文档里不会把它们写成可执行脚本包。

## 基本目录

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

## 已落地模型包

可用 `models.sh` 管理：

| bundle | 作用 | 当前状态 |
|---|---|---|
| `heroine-i2v-core` | AI 女主图生视频主线 | 已落地 |
| `heroine-t2v-explore` | 文生视频探索，不作为主生产路径 | 已落地 |

常用命令：

```bash
./scripts/models.sh list
./scripts/models.sh status
./scripts/models.sh plan heroine-i2v-core
./scripts/models.sh status heroine-i2v-core
```

显式下载：

```bash
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core
```

视频模型较大，下载前先看计划和磁盘空间：

```bash
./scripts/models.sh plan heroine-i2v-core
df -h ComfyUI/models
```

## 规划中模型包

这些名字可以作为后续 catalog 目标，但当前不是可执行 bundle：

```text
heroine-image-core       女主身份图、封面、首帧
heroine-image-edit       变装、局部编辑
heroine-fashion-tryon    商品试穿
```

这些阶段先通过页面模板、ComfyUI-Manager 或社区热门 workflow 探索。等某条 workflow 稳定后，再把它的模型清单沉淀到 `configs/models/catalog.yaml`。

## 页面下载模型

页面下载适合探索和补缺：

1. 打开 ComfyUI。
2. 导入业务 workflow、模板或自带蓝图。
3. 如果页面提示缺少模型，先看节点提示的模型名和目录。
4. 通过 ComfyUI-Manager 或 workflow 的模型提示下载。
5. 下载完成后重启 ComfyUI，刷新模型列表。

常用模型最后应沉淀到 `configs/models/catalog.yaml`，否则 Mac 和服务器很难复现。

## models.sh 边界

`models.sh` 只做显式模型资产管理：

```text
list/status/plan   只读，不访问网络
download           显式下载，写入 ComfyUI/models 下的模型资产目录
```

它不会被 `dev.sh bootstrap` 自动调用，也不会静默下载大文件。

它不负责：

```text
自动安装 third-party custom_nodes
自动选择 workflow
自动迁移模型目录
判断社区 workflow 是否可信
```

## 服务器阶段怎么放

服务器磁盘更适合放大模型。建议统一放到数据盘：

```text
/data/wangqiao/ComfyUI/models/
```

不要放到系统盘或用户家目录。视频模型和 Flux/Wan 类模型很容易占几十 GB。

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

## 推荐习惯

- 下载一个模型后，立即记录它用于哪个业务 workflow。
- 每个作品保存 workflow JSON。
- 女主参考图、变装关键帧、视频首帧要放进 `assets/heroine/`，不要只留在 `ComfyUI/output/`。
- 不常用的大模型先移到归档目录，不要长期堆在默认目录。
- 服务器上定期检查磁盘空间。
