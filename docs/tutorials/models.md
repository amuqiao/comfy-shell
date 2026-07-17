# 模型管理

模型管理的目标是让 ComfyUI workflow 能找到所需权重文件，同时保证下载来源和文件内容可复现。

本文分两层：探索阶段先让页面跑通；沉淀阶段再把已确认的模型写入 `configs/models/catalog.yaml`，由 `scripts/models.sh` 做只读检查、严格校验和显式下载。

## 先分清对象

```text
页面模板 / workflow
  -> 在 http://127.0.0.1:8188/ 里打开、导入、点击「Queue / 队列 / 加入队列」的节点流程

模型文件
  -> workflow 运行时加载的权重
  -> 放在 ComfyUI/models/ 下

models.sh bundle
  -> comfy-shell 为复现准备的模型清单
  -> 例如 heroine-i2v-core
  -> 不是页面模板，不是 workflow
  -> 只有 catalog 中确认了来源和 hash 的条目才允许自动下载
```

所以顺序是：

```text
先选模板或导入 workflow
-> 页面提示缺什么模型
-> 补齐缺失模型
-> 跑通成片
-> 用 scripts/models.sh inspect 提取 workflow 引用
-> 再把已确认来源和 hash 的模型沉淀到 configs/models/catalog.yaml
```

## MVP 阶段怎么补模型

页面补模型适合探索和跑通：

1. 打开 ComfyUI。
2. 从「模板 / 所有模板 / Popular / 使用案例 / 生成类型 -> 视频」、blueprints 或社区 workflow 导入业务 workflow。
3. 点击 `Queue / 队列 / 加入队列`。
4. 如果页面提示缺少模型，先看缺失模型名和节点提示目录。
5. 通过 ComfyUI-Manager、页面下载入口或 workflow 提供的模型提示补齐。
6. 只从可信发布源下载模型，记录模型来源、链接和许可证；避免来源不明的镜像包或分享包。
7. 下载完成后重启 ComfyUI 或刷新模型列表。
8. 再次点击 `Queue / 队列 / 加入队列`。

MVP 阶段只要回答这个问题：

```text
当前 workflow 还缺什么模型？
```

不要先问：

```text
我要不要维护 catalog？
我要不要提前下载一整套 bundle？
我要不要把 Mac 和服务器目录统一？
```

这些是跑通后的工程化问题。

## 跑通后的工程化补充

下面内容用于跑通后复现和迁移，不是第一条成片的阻塞项。

### 可靠性规则

workflow PNG 或 JSON 通常只告诉你“节点要加载哪个文件名”，不等于告诉你“应该从哪里下载”。

因此 `models.sh` 按下面规则工作：

```text
inspect
  -> 只从 workflow 中提取模型文件名和建议目录
  -> 不猜下载源, 不写 catalog, 不访问网络

catalog.yaml
  -> 项目唯一的模型复现清单
  -> source.platform 记录来源平台, 例如 huggingface、civitai、liblib、unknown
  -> download.mode 决定脚本行为: auto、manual、blocked
  -> download.method 决定下载方式: huggingface、civitai、browser
  -> auto 必须提供 sha256; huggingface 还需要 repo/path/repo_type; civitai 需要 download url

plan
  -> 只读解释 catalog
  -> 输出 target、source、download.mode 和 download.method
  -> 不检查文件是否已经存在
  -> download.mode=manual 显示 manual 和 source page/target
  -> download.mode=blocked 显示 blocked 和阻塞原因

status
  -> 只读盘点 COMFY_MODEL_ROOT 中的模型现状
  -> 不传 bundle 时检查全部 bundle, 并按 directory/filename 去重
  -> 输出 summary、missing、manual、blocked、bad、conflict 等分组

verify
  -> 严格检查文件存在且 sha256 正确
  -> manual、blocked、missing、bad、conflict、present_unverified 都返回非 0

download
  -> 只下载 download.mode=auto 的条目
  -> 支持 download.method=huggingface 和 download.method=civitai
  -> manual/blocked 会跳过, 最后输出 Summary 和 Next
  -> 文件名必须和 catalog filename 一致
  -> 下载后先校验 sha256, 再写入目标目录
  -> 不把相似文件重命名成 workflow 需要的文件名
```

这条规则牺牲了一点便利性，但避免把“名字相近的模型”当成同一个模型下载，后续 Mac 和服务器复现时也能保持一致。

### 基本目录

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

如果页面提示 `missing model / 缺少模型`，先看节点提示的模型类型，再检查对应目录。

### models.sh 什么时候用

`models.sh` 是可选复现工具。它适合在你已经跑通一条 workflow 以后使用：

```text
我已经知道要长期复用哪条 workflow
我已经知道它需要哪些模型
我想在 Mac 和服务器上复现同一套模型
我不想每次都靠页面提示手工补模型
```

当前已落地的 bundle：

| bundle | 作用 | 说明 |
|---|---|---|
| `retro-anime-photo-core` | 照片转复古动漫风格 | 从 `.data/nodes/批量照片转绘复古动漫风格（LoRA+ControlNet+UltimateSDUpscale）.png` 解析；已确认的 Civitai/Hugging Face 条目为 `auto`，仍无法确认精确来源的条目为 `manual` |
| `heroine-i2v-core` | 图生视频主线模型包 | 给 `scripts/models.sh` 用，不是页面模板 |
| `heroine-t2v-explore` | 文生视频探索模型包 | 非主路径 |

从 workflow 提取模型引用：

```bash
./scripts/models.sh inspect '.data/nodes/批量照片转绘复古动漫风格（LoRA+ControlNet+UltimateSDUpscale）.png'
```

只读查看。`check` 只校验 catalog schema；`list` 只读取 catalog；`plan` 解释 catalog；`status` 盘点模型目录；`verify` 做严格校验；`download` 只下载可自动下载的条目。`status`、`verify`、`plan` 和 `download` 默认读取 `.env`，并要求其中有 `COMFY_MODEL_ROOT`。

`.env.example` 只是复制生成 `.env` 的模板，不作为运行 profile：

```bash
./scripts/models.sh check
./scripts/models.sh list
./scripts/models.sh plan retro-anime-photo-core
./scripts/models.sh status
./scripts/models.sh status retro-anime-photo-core
./scripts/models.sh verify retro-anime-photo-core
```

显式下载：

```bash
./scripts/models.sh download retro-anime-photo-core
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download retro-anime-photo-core
```

`HF_ENDPOINT` 只影响 `download.method=huggingface`，不影响 Civitai。

如果 `plan` 输出 `manual`，说明 catalog 只记录了 workflow 文件名、目标目录和人工下载线索，需要你打开 source page 或作者说明手动下载。
如果输出 `blocked`，说明 catalog 已知道线索但还不满足自动下载条件，例如缺少可信 `sha256`；确认精确文件后补齐 `sha256`，必要时再补 `size_bytes`。

`download` 不会因为某个模型需要手动下载就整体中断。它会继续处理可自动下载的条目，最后输出类似：

```text
Summary:
success: 4
skipped_existing: 0
manual: 2
blocked: 0
failed: 0

Next:
  1. 按 manual 列表打开 source page 下载
  2. 放到 target 路径
  3. 重新执行 status 或 verify
```

注意：

```text
models.sh 不会选择 workflow
models.sh 不会打开 ComfyUI 页面
models.sh 不会替你判断社区 workflow 是否可信
models.sh 不会替你把相似文件当成同一个模型
models.sh 不会被 local.sh bootstrap 自动调用
```

### 后续再沉淀的模型包

这些名字可以作为后续 catalog 目标，但当前不是 MVP 必需项：

```text
heroine-image-core       女主身份图、封面、首帧
heroine-image-edit       变装、局部编辑
heroine-fashion-tryon    商品试穿
```

这些阶段先通过页面模板、ComfyUI-Manager 或社区 workflow 探索。等某条 workflow 稳定后，再把它的模型清单沉淀到 `configs/models/catalog.yaml`。

### 服务器阶段怎么放

服务器磁盘更适合放大模型。建议统一放到数据盘：

```text
/data/wangqiao/ComfyUI/models/
```

不要放到系统盘或用户家目录。视频模型和 Flux/Wan 类模型很容易占几十 GB。

### 什么时候使用 extra_model_paths.yaml

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

本机 MVP 阶段可以暂时不做这一步，避免把重点从成片转移到目录配置。
