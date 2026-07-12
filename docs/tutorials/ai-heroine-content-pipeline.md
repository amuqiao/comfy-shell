# AI 女主短视频 MVP 生产线

本文目标是先跑通一条可发布的 AI 女主竖屏短视频成片：用现成 ComfyUI 模板或 workflow 生成画面片段，再用剪映完成 BGM、字幕、封面和导出。

## 先分清三个东西

不要一开始被 `model bundle`、`workflow`、`template` 混在一起。

```text
模板 / workflow
  -> 你在 http://127.0.0.1:8188/ 页面里打开、导入、拖入、点击「Queue / 队列 / 加入队列」的节点流程
  -> 例如「模板 / 所有模板」、ComfyUI blueprints、别人分享的 workflow JSON 或 PNG

模型
  -> workflow 运行时需要的权重文件
  -> 放在 ComfyUI/models/ 下面
  -> 页面缺什么模型，就按提示补什么模型

heroine-i2v-core
  -> comfy-shell 自己定义的模型包名称
  -> 只给 scripts/models.sh 用来提前下载一组模型
  -> 不是页面模板，不是 workflow，不是你在 ComfyUI 页面里要点击的东西
```

本文主路径是：

```text
先用页面模板或现成 workflow 跑通
-> 页面提示缺模型就补模型
-> 生成 1-3 个 3-5 秒画面片段
-> 剪映合成 8-15 秒 9:16 成片
-> 跑通后再考虑把模型清单沉淀到 models.sh
```

## 这篇文档解决什么

本文只解决一个业务问题：

```text
我怎样用现成 workflow + 自己提供的素材
尽快产出第一条可发布的 AI 女主短视频成片
```

本文不做：

- 不从 0 搭节点。
- 不先训练 LoRA。
- 不先维护模型 catalog。
- 不冒充真实博主或复刻真人身份。
- 不做未授权换脸、声音克隆、原声搬运或水印搬运。

## MVP 心智模型

先让业务闭环跑起来：

```text
素材
  -> 原创 AI 女主图
  -> 热门视频动作和镜头参考
  -> 可用 BGM

ComfyUI 页面
  -> 打开「模板 / 所有模板」/ 打开 blueprints / 导入社区 workflow
  -> 按缺失提示补模型
  -> 生成短视频片段

剪映后期
  -> BGM / 音效 / 字幕 / 封面
  -> 8-15 秒 9:16 竖屏成片

留痕
  -> workflow
  -> prompt
  -> 输入图和输出片段
  -> 成片和封面
  -> BGM 来源和使用范围
```

第一阶段不要追求完美女主一致性、复杂舞蹈和自动化。先让“模板 -> 补模型 -> 出片 -> 后期 -> 可发布成片”跑通。

## 准备素材

第一条视频只准备最低可用素材：

| 素材 | 最低要求 | 用途 |
|---|---|---|
| 女主参考图 | 1 张原创清晰正脸、半身或全身图 | 作为 AI 女主身份起点 |
| 首帧图 | 1 张适合做视频开头的图 | 输入图生视频 workflow |
| 热门视频参考 | 1 条公开视频 | 只拆动作、镜头、节奏，不复制身份 |
| BGM / 音效 | 目标平台内可用曲库、授权音乐或自有音频 | 后期卡点和氛围 |
| 发布目标 | 8-15 秒 9:16 竖屏成片 | 决定片段数量和剪辑节奏 |

可以参考热门视频的：

```text
动作节奏
镜头角度
构图
转场
音乐节奏和卡点方式
```

不要复制热门视频的：

```text
脸
身份
声音
水印
个人标识
未授权原片内容
未授权音乐或音频素材
```

## 第一次运行准备

如果这是第一次在本机运行 comfy-shell：

```bash
./scripts/env.sh use macos-mps
./scripts/check_env.sh --no-network
./scripts/dev.sh bootstrap
```

准备本次实验目录：

```bash
mkdir -p assets/heroine/inputs assets/heroine/keyframes assets/heroine/exports/videos assets/heroine/exports/covers assets/heroine/metadata workflows
```

启动 ComfyUI：

```bash
./scripts/dev.sh start
./scripts/dev.sh status
```

浏览器打开：

```text
http://127.0.0.1:8188
```

看到 `READY system_stats ok` 或页面能正常打开，就进入下一步。

## 选择现成 Workflow

第一优先级是页面里的现成模板和 workflow，不是脚本。

### 路线 A：页面模板

在 ComfyUI 页面里打开模板入口，例如：

```text
模板
所有模板
Popular
```

你的中文页面大致会看到这些分类：

```text
模板
所有模板
Popular
使用案例
工具
快速开始
节点基础
生成类型
  图像
  视频
  音频
  3D模型
  LLM
合作伙伴节点
```

第一条舞蹈视频优先看：

```text
生成类型 -> 视频
使用案例
Popular
所有模板
```

如果页面提供搜索框，再用中英文一起搜：

```text
图生视频
视频
舞蹈
动作
image to video
i2v
wan
dance
motion
video
```

这些词的对应关系：

| 中文页面词 | 英文常见词 | 你要找什么 |
|---|---|---|
| 模板 / 所有模板 | Templates / Browse Templates | 页面内置模板市场 |
| 生成类型 -> 视频 | Video | 视频生成模板 |
| 图生视频 | Image to Video / I2V | 用女主首帧生成短视频 |
| 使用案例 | Use Cases | 官方整理好的可用场景 |
| Popular | Popular | 热门模板 |

选择原则：

```text
节点少
缺失模型提示清楚
依赖少
能上传首帧图
能输出短视频
```

### 路线 B：仓库自带 blueprints

如果页面模板不知道选哪个，先用仓库自带蓝图：

```text
ComfyUI/blueprints/Image to Video (Wan 2.2).json
```

在页面里点击打开 workflow，或者把这个 JSON 拖进画布。

这个 workflow 适合：

```text
已有女主首帧
-> 生成 3-5 秒短视频片段
```

### 路线 C：社区 workflow

如果你导入别人分享的 JSON 或带 workflow metadata 的 PNG，先看三件事：

```text
缺哪些 custom node
缺哪些模型
是否需要复杂环境依赖
```

第一阶段只选能快速跑通的 workflow。不要为了“更强”一口气装很多来源不明的节点。

## 缺模型怎么办

主路径是按页面提示补模型：

```text
导入 workflow
-> 页面或节点提示「missing model / 缺少模型」
-> 记下模型名和应该放置的目录
-> 用 ComfyUI-Manager、页面下载入口或 workflow 提示补齐
-> 确认模型来自可信发布源，并记录模型来源和许可证
-> 重启 ComfyUI 或刷新模型列表
-> 再点击「Queue / 队列 / 加入队列」
```

遇到缺模型时，先不要理解 `heroine-i2v-core`。你只需要知道：

```text
workflow 决定需要什么模型
页面提示缺什么模型
你按提示补什么模型
```

跑通后如果要复现同一套模型，再看 [模型管理](models.md)。

## 生成画面片段

在选好的 workflow 里做最小改动：

```text
替换输入图：选择你的女主首帧图
替换 prompt：描述轻舞蹈或轻走动
其他参数：先保留 workflow 默认值
```

首帧优先满足：

```text
单人主体
脸清楚
身体完整
手部不严重畸形
背景不要太乱
适合 9:16 裁切
```

第一条舞蹈 prompt 先保守：

```text
full body dance, gentle rhythm, the woman sways and steps lightly, smooth motion, stable face, fashion video, studio lighting
```

如果偏走秀：

```text
full body fashion walk, gentle hair movement, confident pose, smooth camera pan
```

第一轮参数目标：

```text
时长：3-5 秒
动作：小幅舞蹈或轻走动
主体：单人
镜头：轻推近或轻横移
分辨率：按 workflow 默认或中等设置
```

点击 `Queue / 队列 / 加入队列`。成功后至少保存：

```text
ComfyUI/output/<本次视频片段>.mp4
assets/heroine/keyframes/<本次首帧>.png
workflows/heroine-i2v-first-video.json
```

如果只生成了 3-5 秒，可以重复生成 2-3 个相近片段。第一条成片不需要复杂剧情，能剪成自然舞蹈片段即可。

## 剪映后期成片

ComfyUI 负责画面素材，剪映负责成片。

在剪映里完成：

```text
新建 9:16 竖屏项目
导入 ComfyUI 输出视频
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

声音策略先保持简单：

```text
主声音：BGM
辅助：轻音效或节奏点
字幕：可选，少量账号人设或商品卖点
配音：第一阶段不做
口型同步：第一阶段不做
```

## Metadata 留痕

把成片信息写进 metadata：

```markdown
# heroine-dance-mvp-001

- workflow: workflows/heroine-i2v-first-video.json
- workflow_source: <页面模板 / blueprints / 社区 workflow>
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

## 发布前检查

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

完成后至少留下这些文件：

```text
assets/heroine/keyframes/<本次首帧>.png
ComfyUI/output/<本次视频片段>.mp4
assets/heroine/exports/videos/heroine-dance-mvp-001.mp4
assets/heroine/exports/covers/heroine-dance-mvp-001-cover.png
assets/heroine/metadata/heroine-dance-mvp-001.md
workflows/heroine-i2v-first-video.json
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

## 每日最小 SOP

每天只做这个闭环：

```text
1. 选一个热门视频，拆动作、镜头和音乐卡点。
2. 选一个女主参考图或关键帧。
3. 在 ComfyUI 页面从「模板 / 所有模板 / 生成类型 -> 视频」选择模板，或导入现成 workflow。
4. 按页面缺失提示补模型。
5. 输出 1-3 个 3-5 秒视频片段。
6. 剪映合成 8-15 秒 9:16 成片。
7. 做发布前检查。
8. 保存输入图、输出视频、成片、封面、workflow、prompt、BGM 曲名、BGM 来源和 BGM 使用范围。
```

## 复现评审清单

如果你照着本文做完，应该能回答这些问题：

```text
我用了哪张原创女主首帧？
我导入了哪个页面模板或现成 workflow？
页面提示缺了哪些模型，我怎么补齐的？
我生成了几个 3-5 秒画面片段？
我选了哪段可用 BGM？
我用剪映导出了哪个 8-15 秒 9:16 成片？
我导出了哪张封面？
我把成片、封面、workflow、prompt、BGM 曲名、BGM 来源、BGM 链接或授权凭据、BGM 使用范围保存在哪里？
```

如果其中任意一个问题答不上来，说明生产线还没有真正跑通。

## 跑通以后再做什么

跑通第一条成片后，再考虑这些事情：

```text
整理女主身份资产库
沉淀稳定 workflow
把常用模型清单写入 configs/models/catalog.yaml
用 scripts/models.sh 在 Mac 和服务器复现模型
探索变装、试穿、动作控制、LoRA
```

这时再看模型包命令：

```bash
./scripts/models.sh list
./scripts/models.sh plan heroine-i2v-core
```

`heroine-i2v-core` 的意思是“图生视频主线模型包”。它用于以后在 Mac 和服务器复现同一套模型，不是 MVP 第一入口。

第一阶段先避免：

```text
从零搭节点
训练 LoRA
做复杂多镜头
做多人视频
一开始写模型 catalog
一开始依赖 models.sh
一开始做声音克隆、复杂配音或口型同步
```

先跑通业务，再优化工程化。
