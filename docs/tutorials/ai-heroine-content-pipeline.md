# AI 女主短视频 MVP 生产线

本文目标是用可用素材和成熟 workflow，先产出一条可发布的 AI 女主竖屏短视频成片，再逐步沉淀原创女主资产、舞蹈动作、变装、试穿和日更生产线。

## 这篇文档解决什么

本文只解决一个业务问题：

```text
我怎样用现成 workflow + 自己提供的素材
尽快产出第一条可发布的 AI 女主短视频成片
```

本文负责：

- 告诉你先准备哪些素材。
- 告诉你优先复用哪些现成 workflow。
- 告诉你第一条可发布视频的最短路径。
- 告诉你声音、剪辑和发布检查怎么接上。
- 告诉你哪些事情先不要做。
- 告诉你跑通后如何沉淀女主资产和生产线。

本文不负责：

- 冒充真实博主或复刻真人身份。
- 未授权换脸、声音克隆或把真人转成敏感内容。
- 复用未授权音乐、音频、原片水印或他人个人标识。
- 规避平台审核或制作违规内容。
- 从 0 讲解节点原理。

## 心智模型

先用素材驱动，不要用节点驱动：

```text
你提供素材
  -> 女主参考图
  -> 热门视频参考
  -> 服装/商品图
  -> 发布目标

复用成熟 workflow
  -> ComfyUI templates
  -> ComfyUI blueprints
  -> ComfyUI-Manager 可安装节点包
  -> 社区热门 workflow

最小改动
  -> 替换输入图
  -> 替换 prompt
  -> 选择模型
  -> 调少量参数

画面素材
  -> 首帧/关键帧
  -> 3-5 秒视频
  -> 可复用 workflow

后期成片
  -> 剪映 / CapCut / PR
  -> BGM / 音效 / 字幕 / 封面
  -> 8-15 秒 9:16 竖屏成片
  -> 发布前检查
```

第一阶段不要追求完美女主一致性。先让“输入图 -> 视频素材 -> 后期合成 -> 可发布成片”这条链路跑通。

## 内容边界

可以参考真实热门视频的：

```text
动作节奏
镜头角度
构图
转场
服装品类
拍摄脚本
音乐节奏和卡点方式
```

不要直接复刻真实博主的：

```text
脸
身份
声音
水印
个人标识
未授权原片内容
未授权音乐或音频素材
```

正确做法是：热门视频作为动作和镜头参考，主角必须是原创 AI 女主。

## MVP 素材清单

第一条视频不要等资产库完美。先准备这些可用素材：

| 素材 | 最低要求 | 用途 |
|---|---|---|
| 女主参考图 | 1 张清晰正脸或半身图，原创，不是真人复刻 | 作为 AI 女主身份起点 |
| 首帧图 | 1 张适合做视频开头的图，可以由女主参考图编辑得到 | 输入图生视频 workflow |
| 热门视频参考 | 1 条你想学习的公开视频 | 拆动作、镜头、节奏，不复制身份 |
| 服装/商品图 | 可选，清晰单品图 | 变装或试穿关键帧 |
| BGM / 音效 | 使用目标平台内可用曲库、授权音乐或自有音频 | 后期卡点和成片氛围 |
| 发布目标 | 8-15 秒 9:16 竖屏成片 | 决定画面片段、剪辑节奏和导出规格 |

如果你现在只有一张女主图，也可以先跑：

```text
女主参考图
-> 图生视频 workflow
-> 轻动作 prompt
-> 3-5 秒视频
-> 剪映加 BGM、字幕、封面
-> 8-15 秒竖屏成片
```

## 成熟 workflow 优先级

不要从零造轮子，按这个顺序找 workflow：

### 1. ComfyUI 自带 blueprints

优先使用仓库里已经存在的蓝图：

```text
ComfyUI/blueprints/Image to Video (Wan 2.2).json
ComfyUI/blueprints/Text to Video (Wan 2.2).json
ComfyUI/blueprints/Text to Image.json
```

当前主生产路径优先用：

```text
Image to Video (Wan 2.2)
```

它适合“已有女主首帧 -> 生成短视频”。

### 2. ComfyUI templates

页面里打开：

```text
浏览模板 / Browse Templates
```

适合找：

```text
image to video
text to image
image edit
try-on
inpaint
outpaint
```

模板比从零搭节点更适合第一阶段。

### 3. ComfyUI-Manager 和社区热门 workflow

导入别人分享的 JSON 或带 workflow metadata 的 PNG 时，先看三件事：

```text
是否缺 custom node
是否缺模型
是否需要很复杂的环境依赖
```

第一阶段选择“缺少东西少、模型来源清楚、节点包可信”的 workflow。不要一上来装一堆来源不明的节点。

## 第一条可发布视频最短路径

目标：先产出一条 8-15 秒、9:16、带声音、可发布的舞蹈类竖屏成片。

### 首次运行前置检查

如果这是第一次在本机运行 comfy-shell，先准备环境：

```bash
./scripts/env.sh use macos-mps
./scripts/check_env.sh --no-network
./scripts/dev.sh bootstrap
```

如果已经 bootstrap 过，直接从步骤 1 开始。

先准备本次实验目录：

```bash
mkdir -p assets/heroine/inputs assets/heroine/keyframes assets/heroine/exports/videos assets/heroine/exports/covers assets/heroine/metadata workflows
```

### 步骤 1：启动 ComfyUI

```bash
./scripts/dev.sh start
./scripts/dev.sh status
```

浏览器打开：

```text
http://127.0.0.1:8188
```

### 步骤 2：导入图生视频 workflow

页面点击 `打开工作流`，选择：

```text
ComfyUI/blueprints/Image to Video (Wan 2.2).json
```

也可以把这个 JSON 直接拖到画布里。

### 步骤 3：准备模型

先看下载计划：

```bash
./scripts/models.sh plan heroine-i2v-core
```

确认磁盘空间：

```bash
df -h ComfyUI/models
```

显式下载：

```bash
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core
```

如果你不想用脚本，也可以按页面缺模型提示下载。两种方式都可以；脚本适合以后 Mac 和服务器复现。

### 步骤 4：替换输入图

在 workflow 里找到 `Load Image` 或图片输入节点，选择你的女主首帧图。

首帧优先满足：

```text
单人主体
脸清楚
手部不畸形
背景不要太乱
适合竖屏裁切
```

### 步骤 5：写轻舞蹈 prompt

第一条视频不要复杂舞蹈。先做轻动作，让身体自然：

```text
full body dance, gentle rhythm, the woman sways and steps lightly, smooth motion, stable face, fashion video, studio lighting
```

如果是全身走秀：

```text
full body fashion walk, gentle hair movement, confident pose, smooth camera pan
```

### 步骤 6：先用保守参数

第一轮只验证链路：

```text
时长：3-5 秒
动作：小幅舞蹈或轻走动
主体：单人
镜头：轻推近或轻横移
分辨率：按 workflow 默认或中等设置
```

不要同时大改帧数、分辨率、steps、motion、prompt 和输入图。

### 步骤 7：Queue 并保存画面素材

点击 `Queue`。成功后保存：

```text
ComfyUI/output/                         输出视频
assets/heroine/keyframes/               输入首帧
workflows/heroine-i2v-first-video.json  当前 workflow
```

如果只生成了 3-5 秒，可以重复步骤 4-7 产出 2-3 个相近片段。第一条成片不需要复杂剧情，能剪成自然舞蹈片段即可。

### 步骤 8：导入剪映做后期

ComfyUI 负责画面素材，剪映负责成片：

```text
导入 ComfyUI 输出视频
裁切或新建 9:16 竖屏项目
按音乐节奏排列 1-3 个片段
删掉明显畸形、闪烁、变脸的片段
加 BGM、必要音效、字幕和封面
选择最稳定的一帧作为封面，或从成片中截图保存封面
导出 8-15 秒成片
保存到 assets/heroine/exports/videos/
```

第一条视频优先用目标平台内可用曲库、授权音乐或自有音频。平台曲库通常只适合在对应平台内发布；如果要跨平台分发或二次剪辑，按音乐授权范围重新确认。不要克隆真人声音，不要直接搬运热门视频原声。

建议命名：

```text
assets/heroine/exports/videos/heroine-dance-mvp-001.mp4
assets/heroine/exports/covers/heroine-dance-mvp-001-cover.png
assets/heroine/metadata/heroine-dance-mvp-001.md
```

### 步骤 9：声音和节奏

舞蹈类视频的声音策略先保持简单：

```text
主声音：BGM
辅助：轻音效或节奏点
字幕：可选，少量账号人设或商品卖点
配音：第一阶段不做
口型同步：第一阶段不做
```

判断声音是否过关：

```text
音乐节奏和动作节奏基本对齐
没有明显音画脱节
没有突兀噪声、爆音或断点
不用未授权真人声音
不用带水印或来源不清的原声
```

把 BGM 来源写进 metadata 文件：

```markdown
# heroine-dance-mvp-001

- workflow: workflows/heroine-i2v-first-video.json
- model_bundle: heroine-i2v-core
- prompt: full body dance, gentle rhythm...
- input_keyframe: assets/heroine/keyframes/<本次首帧>.png
- output_clip: ComfyUI/output/<本次视频片段>.mp4
- final_video: assets/heroine/exports/videos/heroine-dance-mvp-001.mp4
- cover: assets/heroine/exports/covers/heroine-dance-mvp-001-cover.png
- bgm_title: <具体曲名或音频文件名>
- bgm_source: <目标平台曲库 / 授权音乐站点 / 自有音频>
- bgm_platform_or_library: <抖音曲库 / CapCut 曲库 / 授权站点名 / 本地文件>
- bgm_link_or_license_id: <曲库链接 / 授权凭据编号 / 本地文件路径>
- bgm_usage_scope: <仅目标平台 / 可跨平台 / 自用测试>
- failed_clip_notes: <失败片段原因>
```

### 步骤 10：发布前检查

导出前逐项看：

```text
画面：9:16 竖屏，主体完整，脸和身材稳定
动作：舞蹈自然，没有严重肢体扭曲、手脚穿帮、突然变脸
声音：BGM 清楚，卡点自然，没有未授权声音复制
剪辑：节奏顺，开头 1 秒能留住人，结尾不突兀
字幕：不遮脸、不遮商品、不堆字
封面：主体清楚，能看出女主人设或舞蹈主题
合规：不冒充真人，不保留他人水印、昵称、个人标识
```

这才是第一条业务闭环。

完成后至少留下这些文件：

```text
assets/heroine/keyframes/<本次首帧>.png
ComfyUI/output/<本次视频片段>.mp4
assets/heroine/exports/videos/heroine-dance-mvp-001.mp4
assets/heroine/exports/covers/heroine-dance-mvp-001-cover.png
assets/heroine/metadata/heroine-dance-mvp-001.md
workflows/heroine-i2v-first-video.json
```

metadata 里至少记录：

```text
prompt
使用的 workflow
使用的模型包
BGM 来源
BGM 曲名或音频文件名
BGM 平台、曲库、链接或授权凭据
BGM 授权或使用范围
失败片段原因
```

## 热门视频怎么用

热门视频不是拿来换脸，而是拆成脚本：

```text
0.0s-1.0s  全身站姿，轻微摆动
1.0s-2.0s  向镜头走近，右手整理头发
2.0s-3.0s  转身展示裙摆
3.0s-4.0s  回头定格，适合放商品卖点字幕
4.0s-8.0s  重复最稳动作，给 BGM 卡点
```

再翻译成 prompt：

```text
full body fashion pose, the woman slowly turns around, gentle hair movement, smooth camera pan, confident expression
```

如果 workflow 支持姿态、深度、边缘或视频参考控制，再把热门视频抽成控制素材；如果不支持，第一阶段只用文字拆解，不要为了动作控制卡住。声音只参考节奏，不复制原声。

## 变装和试穿怎么接入

变装/试穿不是第一条视频的阻塞项。跑通图生视频后再接入。

最短路径：

```text
女主参考图
-> 图片编辑/换装 workflow
-> 变装后关键帧
-> 图生视频 workflow
-> 短视频
```

输入素材：

```text
女主标准图
服装/商品图
目标场景 prompt
```

输出素材：

```text
试穿正面图
试穿侧面图
商品细节图
视频首帧
封面图
可剪辑视频片段
```

验收标准：

- 观众能认出是同一个 AI 女主。
- 衣服形态和商品图接近。
- 画面可以作为视频首帧。
- 不因为追求换装导致脸和身材严重漂移。
- 后期加 BGM 后能剪成自然竖屏成片。

## 女主资产库什么时候做

第一条视频跑通后，再做资产库。

目录结构：

```text
assets/heroine/
  identity/
    face-front.png
    half-body.png
    full-body-front.png
    full-body-side.png
    full-body-back.png
  expressions/
  outfits/
  keyframes/
  references/
    motion/
    music/
  exports/
    videos/
    covers/
```

需要长期一致的是：

```text
脸
身材比例
年龄感
气质
发型/发色主设定
辨识度特征
账号人设
```

可以变化的是：

```text
穿搭
妆容
场景
动作
镜头语言
音乐和卡点
情绪
风格尺度
```

所以目标不是固定穿搭，而是固定“观众能认出来这是同一个 AI 女主”。

## 什么时候训练 LoRA

不要一开始训练 LoRA。

先用参考图方式跑通：

```text
20-50 张女主稳定素材
3-5 套服装
3-5 个表情
多角度图
几条成功视频
```

当你已经知道哪张脸、哪种身材、哪种气质适合账号，再把高质量图片整理成训练集。

## 每日最小 SOP

每天只做这个闭环：

```text
1. 选一个热门视频，拆动作、镜头和音乐卡点。
2. 选一个女主参考图或关键帧。
3. 选一段可用 BGM，优先目标平台内可用曲库、授权音乐或自有音频。
4. 可选：选一件衣服或商品。
5. 生成或编辑 1-3 张首帧。
6. 选最稳的首帧跑图生视频。
7. 输出 1-3 个 3-5 秒视频片段。
8. 剪映合成 8-15 秒 9:16 成片。
9. 做发布前检查。
10. 保存输入图、输出视频、成片、封面、workflow、prompt、模型、BGM 曲名、BGM 来源和 BGM 使用范围。
```

## 复现评审清单

如果你照着本文做完，应该能回答这些问题：

```text
我用了哪张原创女主首帧？
我导入了哪个现成 workflow？
我下载或确认了哪个模型包？
我生成了几个 3-5 秒画面片段？
我选了哪段可用 BGM？
我用剪映导出了哪个 8-15 秒 9:16 成片？
我导出了哪张封面？
我把成片、封面、workflow、prompt、模型、BGM 曲名、BGM 来源、BGM 链接或授权凭据、BGM 使用范围保存在哪里？
```

如果其中任意一个问题答不上来，说明生产线还没有真正跑通。

## 当前可执行模型包

已落地到 `configs/models/catalog.yaml` 的模型包：

```text
heroine-i2v-core         图生视频主线
heroine-t2v-explore      文生视频探索，不作为主生产路径
```

查看：

```bash
./scripts/models.sh list
./scripts/models.sh plan heroine-i2v-core
```

规划中，暂未标准化到 catalog：

```text
heroine-image-core       女主身份图、封面、首帧
heroine-image-edit       变装、局部编辑
heroine-fashion-tryon    商品试穿
```

这些阶段先通过页面模板、ComfyUI-Manager 或社区 workflow 探索。稳定后再加入 `configs/models/catalog.yaml`。

## 不要现在做什么

第一阶段先避免：

```text
从零搭节点
训练 LoRA
做复杂多镜头
做多人视频
同时换模型、换 prompt、换分辨率、换动作控制
为了省下载成本使用过时轻量模型
一开始做声音克隆、复杂配音或口型同步
```

先跑通业务，再优化质量。
