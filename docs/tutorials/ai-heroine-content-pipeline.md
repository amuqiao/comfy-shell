# AI 女主短视频 MVP 生产线

本文目标是先跑通一条可发布的 AI 女主竖屏短视频成片：用你的原创 AI 女主素材和一段目标舞蹈参考视频，借助现成 ComfyUI 模板或 workflow 生成同动作、同节奏的 AI 女主视频片段，再用剪映完成 BGM、字幕、封面和导出。

你的业务目标很具体：

```text
做一个原创 AI 女主账号
先产出一条能发布的竖屏舞蹈 MVP 视频
以后每天用热门动作、镜头和音乐节奏做新内容
再逐步扩展到变装、试穿和女装带货
```

所以本文不是 ComfyUI 基础课。它只教你把第一条业务视频跑出来。

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
先准备 AI 女主素材和目标舞蹈参考视频
-> 用页面模板或现成 workflow 跑通动作参考到 AI 女主视频
-> 页面提示缺模型就补模型
-> 生成 1-3 个 3-5 秒 AI 女主舞蹈片段
-> 剪映合成 8-15 秒 9:16 成片
-> 跑通后再考虑把模型清单沉淀到 models.sh
```

## 这篇文档解决什么

本文只解决一个业务问题：

```text
我怎样用现成 workflow + 自己的 AI 女主素材 + 目标舞蹈参考视频
尽快产出第一条同动作、同节奏、可发布的 AI 女主短视频成片
```

本文不做：

- 不从 0 搭节点。
- 不先训练 LoRA。
- 不先维护模型 catalog。
- 不冒充真实博主或复刻真人身份。
- 不做未授权换脸、声音克隆、原声搬运或水印搬运。

## 本教程的目标视频

照着本文操作，目标产物是：

```text
一条 8-15 秒 9:16 竖屏舞蹈短视频
主角是原创 AI 女主
动作来自你提供的目标舞蹈参考视频
节奏和镜头参考目标视频，但不复刻真人身份
有 BGM / 必要音效 / 可选字幕 / 封面
能作为抖音发布前的 MVP 成片
```

长期目标是稳定 AI 女主，但第一条视频先不因为“完美一致性”卡住。它只验收一件事：

```text
我能不能从 0 准备角色图
-> 生成首帧
-> 把目标舞蹈视频拆成动作参考或控制素材
-> 用支持动作参考的 video workflow 出片
-> 用剪映合成可发布成片
```

## 今天照这个顺序做

这是本文的主线。不要跳步，不要先优化。

```text
1. 打开 ComfyUI 页面。
2. 在「模板 / 所有模板 / Popular / 生成类型 -> 图像」找人物或文生图模板。
3. 生成 3 张原创 AI 女主身份图：正脸、半身、全身正面。
4. 在「模板 / 所有模板 / 使用案例 / 生成类型 -> 图像」找图片编辑或图生图模板。
5. 把全身图调整成一张适合跳舞视频的视频首帧。
6. 准备一段目标舞蹈参考视频，先裁成 3-5 秒可控片段。
7. 在「模板 / 所有模板 / Popular / 生成类型 -> 视频」找支持动作参考、姿态控制或视频参考的模板。
8. 把视频首帧和目标舞蹈参考视频放进去，按页面提示补模型。
9. 生成 1-3 个 3-5 秒 AI 女主舞蹈片段。
10. 用剪映按目标视频节奏加 BGM、字幕、封面，导出 8-15 秒 9:16 成片。
11. 保存 workflow、prompt、素材、目标视频来源、成片和 BGM 来源。
```

如果页面模板不知道怎么选，就按本文给出的仓库 blueprints 兜底。blueprints 不是最热门模板，但它们是本仓库当前能直接找到的现成 workflow，适合兜底跑通。

## 本教程使用哪些现成 Workflow

先用页面模板。页面里的 `Popular` 会变化，所以本文不绑定某个固定模板名，而是绑定你要找的模板类型。找不到合适模板时，再用仓库自带 blueprints 兜底。

| 阶段 | 中文页面入口 | 搜索词 | 仓库兜底 blueprint |
|---|---|---|---|
| 生成 AI 女主角色图 | `模板 / 所有模板 / Popular / 生成类型 -> 图像` | `人物`、`角色`、`全身`、`文生图`、`portrait`、`full body` | `ComfyUI/blueprints/Text to Image (Flux.2 Dev).json`、`ComfyUI/blueprints/Text to Image (Qwen-Image 2512).json`、`ComfyUI/blueprints/Text to Image.json` |
| 生成或编辑视频首帧 | `模板 / 所有模板 / 使用案例 / 生成类型 -> 图像` | `图片编辑`、`图生图`、`换装`、`image edit` | `ComfyUI/blueprints/Image Edit (Flux.2 Dev).json`、`ComfyUI/blueprints/Image Edit (Qwen 2511).json` |
| 提取目标视频动作 | `模板 / 所有模板 / 使用案例 / 生成类型 -> 视频` | `姿态`、`动作`、`pose`、`video to pose`、`motion` | `ComfyUI/blueprints/Video to Pose Map (SDPose Multi-Person).json`、`ComfyUI/blueprints/Get Any Video Frame.json` |
| 生成 AI 女主舞蹈片段 | `模板 / 所有模板 / Popular / 生成类型 -> 视频` | `动作参考`、`姿态控制`、`图生视频`、`pose to video`、`motion transfer`、`video reference`、`i2v` | `ComfyUI/blueprints/Pose to Video (LTX 2.0).json`、`ComfyUI/blueprints/Image to Video (Wan 2.2).json` |
| 后期成片 | 剪映 / CapCut / PR | BGM、字幕、封面、9:16 | 不在 ComfyUI 里做 |

第一优先级是能使用目标视频动作的 workflow，例如 `Pose to Video`、`Video to Pose Map`、`motion transfer`、`video reference`。普通 `Image to Video` 只能做兜底：它可以参考你的 prompt 和首帧，但不能稳定复刻目标舞蹈动作。

## 本教程产物链路

每个业务产出步骤都应该留下可复现资产。最后不是“生成了一个片段”就结束，而是得到一条可发布成片。

```text
目标舞蹈参考视频
-> 动作、镜头、节奏拆解
-> AI 女主身份图
-> 视频首帧
-> 目标舞蹈视频裁剪片段
-> 姿态图 / 动作控制素材 / 视频参考
-> AI 女主舞蹈 workflow
-> 3-5 秒 AI 女主舞蹈片段
-> 剪映 BGM / 字幕 / 封面
-> 8-15 秒 9:16 可发布成片
-> workflow / prompt / 目标视频来源 / 控制素材 / BGM 来源留痕
```

第一阶段先不追求训练级角色一致性、复杂舞蹈和自动化，但要保留同一个主身份。先让“模板 -> 补模型 -> 出片 -> 后期 -> 可发布成片”跑通。

## 步骤 1：准备素材

第一条视频只准备最低可用素材。目标舞蹈参考视频是必需项，不是可选项。

| 素材 | 最低要求 | 用途 |
|---|---|---|
| 女主参考图 | 1 张原创清晰正脸、半身或全身图；没有就按步骤 3 生成 | 作为 AI 女主身份起点 |
| 首帧图 | 1 张适合做视频开头的图；没有就按步骤 4 生成 | 输入动作参考或视频生成 workflow |
| 目标舞蹈参考视频 | 1 条公开视频或你有权使用的视频，先裁出 3-5 秒目标动作片段 | 提供舞蹈动作、节奏、镜头参考 |
| BGM / 音效 | 目标平台内可用曲库、授权音乐或自有音频 | 后期卡点和氛围 |
| 发布目标 | 8-15 秒 9:16 竖屏成片 | 决定片段数量和剪辑节奏 |

可以从目标舞蹈视频参考：

```text
动作节奏
镜头角度
构图
转场
音乐节奏和卡点方式
```

不要复制目标视频的：

```text
脸
身份
声音
水印
个人标识
未授权原片内容
未授权音乐或音频素材
```

## 步骤 2：第一次运行准备

如果这是第一次在本机运行 comfy-shell：

```bash
./scripts/env.sh use macos-mps
./scripts/check_env.sh --no-network
./scripts/dev.sh bootstrap
```

准备本次实验目录：

```bash
mkdir -p assets/heroine/inputs assets/heroine/references assets/heroine/identity assets/heroine/keyframes assets/heroine/control assets/heroine/exports/videos assets/heroine/exports/covers assets/heroine/metadata workflows
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

本步骤的验收结果是：

```text
http://127.0.0.1:8188 能打开
实验目录已创建
ComfyUI 状态可检查
```

## 步骤 3：生成 AI 女主角色图

如果你已经有可用的原创女主图，可以跳过本步骤，直接进入步骤 4。

本步骤的产物是 3 张身份图，不是视频：

```text
assets/heroine/identity/face-front.png
assets/heroine/identity/half-body.png
assets/heroine/identity/full-body-front.png
```

### 3.1 选择模板

在中文页面优先打开：

```text
模板
所有模板
Popular
生成类型 -> 图像
```

搜索：

```text
人物
角色
全身
文生图
portrait
full body
text to image
```

看到合适模板后：

```text
打开模板
保留原 workflow 结构
固定同一模型、同一角色描述和 seed
只改必要的 prompt、尺寸和输入图
点击 Queue / 队列 / 加入队列
如果提示缺模型，先按步骤 7 的规则补模型
```

如果页面模板找不到合适的，用仓库自带 blueprint：

```text
ComfyUI/blueprints/Text to Image (Flux.2 Dev).json
ComfyUI/blueprints/Text to Image (Qwen-Image 2512).json
ComfyUI/blueprints/Text to Image.json
```

### 3.2 生成三张基础角色图

先生成 3 类图，不要一上来追求完整三视图：

```text
正脸头像
半身图
全身正面图
```

推荐 prompt：

```text
original adult female virtual influencer, recognizable face, elegant confident temperament, consistent body proportion, fashion creator, clean studio lighting, high quality portrait
```

全身图可以补充：

```text
full body, standing pose, simple background, clear face, natural hands, fashion outfit, vertical composition
```

生成顺序建议：

```text
先出正脸头像，确定脸和气质，选 1 张作为主身份图
如果模板支持参考图或图片编辑，用主身份图派生半身图和全身正面图
如果模板只支持文生图，就固定同一套角色描述和 seed，多出几张，选最像同一个人的 3 张
最后选全身正面图作为后续视频首帧的基础
```

保存为：

```text
assets/heroine/identity/face-front.png
assets/heroine/identity/half-body.png
assets/heroine/identity/full-body-front.png
```

这里的原则是“先有一个主身份，再扩展视图”。不要三张图都随便生成，否则很容易变成三个不同的人。

### 3.3 角色图验收

能进入下一步的标准：

```text
脸清楚
像同一个人
全身图身体比例正常
手部没有严重畸形
画面适合裁成 9:16
```

侧面、背面、多表情、多服装不是第一条视频的阻塞项。第一条 MVP 只要有一张稳定全身或半身首帧即可。

## 步骤 4：生成视频首帧

首帧是 AI 女主进入目标舞蹈动作前的第一帧。你可以直接用步骤 3 生成的 `full-body-front.png`，也可以用图片编辑模板稍微调整。

本步骤的产物是：

```text
assets/heroine/keyframes/heroine-dance-mvp-001-keyframe.png
```

优先入口：

```text
模板
所有模板
使用案例
生成类型 -> 图像
```

搜索：

```text
图片编辑
图生图
换装
image edit
```

看到合适模板后：

```text
上传或选择 assets/heroine/identity/full-body-front.png
把 prompt 改成目标舞蹈视频第一秒附近的站姿、镜头角度和服装状态
保持角色脸和身体比例稳定
点击 Queue / 队列 / 加入队列
```

可用 blueprint：

```text
ComfyUI/blueprints/Image Edit (Flux.2 Dev).json
ComfyUI/blueprints/Image Edit (Qwen 2511).json
```

首帧 prompt：

```text
full body dance starting pose, confident expression, vertical 9:16 composition, natural hands, stable face, same character identity
```

保存为：

```text
assets/heroine/keyframes/heroine-dance-mvp-001-keyframe.png
```

首帧验收：

```text
单人主体
脸清楚
身体完整
手部不严重畸形
背景不要太乱
适合 9:16 裁切
```

## 步骤 5：准备目标舞蹈参考视频

本步骤的产物是：

```text
assets/heroine/references/target-dance-mvp-001.mp4
assets/heroine/metadata/target-dance-mvp-001-breakdown.md
```

目标视频不是拿来换脸，也不是直接搬运。它只提供：

```text
动作顺序
身体姿态
镜头运动
节奏卡点
构图参考
```

先把目标视频裁成 3-5 秒。不要一开始就用完整 15 秒视频，动作越长越容易失控。第一条 MVP 只选一个最稳动作片段：

```text
0.0s-1.0s  起始站姿或入场动作
1.0s-2.5s  核心舞蹈动作
2.5s-4.0s  转身、摆手或定格
4.0s-5.0s  可选结尾动作
```

把它保存为：

```text
assets/heroine/references/target-dance-mvp-001.mp4
```

同时写一份动作拆解：

```markdown
# target-dance-mvp-001-breakdown

- source: <目标视频来源>
- allowed_use: <公开视频参考 / 已授权 / 自有素材>
- clip_path: assets/heroine/references/target-dance-mvp-001.mp4
- duration: 3-5s
- frame_ratio: 9:16
- action_0_1s: <起始姿态>
- action_1_2_5s: <核心动作>
- action_2_5_4s: <转身/摆手/定格>
- camera: <固定镜头 / 推近 / 横移>
- rhythm_notes: <卡点位置>
- do_not_copy: face, identity, watermark, nickname, original voice
```

如果你不知道怎么拆，就先按肉眼写 3 行：起手、核心动作、结束动作。动作控制 workflow 会尽量从视频或姿态图里取动作；文字拆解是为了你后期判断生成结果是否跑偏。

## 步骤 6：选择动作参考 Video Workflow

第一优先级是页面里的现成模板和 workflow，不是脚本。

本步骤只做一件事：选一个能接收 AI 女主首帧和目标舞蹈参考视频，或者能接收姿态图/动作控制素材并输出视频的 workflow。

本步骤的产物是：

```text
workflows/heroine-dance-motion-mvp-001.json
```

选中模板或导入 workflow 后，先保存或导出 workflow，再继续补模型和生成视频。这样即使后面报错、刷新页面或换模板，也能知道本次到底从哪条 workflow 开始。

### 6.1 页面模板

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
动作参考
姿态控制
视频参考
图生视频
pose to video
video to pose
motion transfer
video reference
dance
motion
```

这些词的对应关系：

| 中文页面词 | 英文常见词 | 你要找什么 |
|---|---|---|
| 模板 / 所有模板 | Templates / Browse Templates | 页面内置模板市场 |
| 生成类型 -> 视频 | Video | 视频生成模板 |
| 姿态控制 | Pose Control / Pose to Video | 用目标视频姿态驱动 AI 女主动作 |
| 视频参考 | Video Reference / Motion Transfer | 用目标视频提供动作和节奏 |
| 图生视频 | Image to Video / I2V | 兜底方案，只用女主首帧和文字描述生成短视频 |
| 使用案例 | Use Cases | 官方整理好的可用场景 |
| Popular | Popular | 热门模板 |

选择原则：

```text
节点少
缺失模型提示清楚
依赖少
能上传首帧图
能上传目标舞蹈参考视频，或能接收姿态图 / 深度图 / 边缘图
能输出短视频
```

不要选这些作为第一条视频：

```text
需要训练角色 LoRA 的 workflow
需要真人换脸或身份复刻的 workflow
需要先训练角色模型才能出片的 workflow
需要大量来源不明 custom nodes 的 workflow
```

### 6.2 仓库自带 blueprints

如果页面模板不知道选哪个，按这个顺序试仓库自带蓝图：

```text
ComfyUI/blueprints/Video to Pose Map (SDPose Multi-Person).json
ComfyUI/blueprints/Pose to Video (LTX 2.0).json
ComfyUI/blueprints/Image to Video (Wan 2.2).json
```

在页面里点击打开 workflow，或者把 JSON 拖进画布。

它们的职责不同：

```text
Video to Pose Map
  -> 从目标舞蹈视频提取姿态控制素材

Pose to Video
  -> 用姿态控制素材驱动 AI 女主生成舞蹈片段

Image to Video
  -> 只有首帧和 prompt 的兜底方案，不能稳定复刻目标舞蹈
```

如果你完全不知道怎么打开仓库 blueprint，可以在 ComfyUI 页面把上面的 JSON 文件拖进画布。导入后不要先改节点结构，只替换输入图、目标视频、姿态图和 prompt。

导入后先复制或导出一份：

```text
workflows/heroine-dance-motion-mvp-001.json
```

### 6.3 社区 workflow

如果你导入别人分享的 JSON 或带 workflow metadata 的 PNG，先看三件事：

```text
缺哪些 custom node
缺哪些模型
是否需要复杂环境依赖
```

第一阶段只选能快速跑通的 workflow。不要为了“更强”一口气装很多来源不明的节点。

## 步骤 7：缺模型就按页面提示补模型

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

第一条视频只需要把当前 workflow 缺的模型补齐。不要在这一步提前下载一整套你还没用到的模型包。

## 步骤 8：生成 3-5 秒 AI 女主舞蹈片段

在选好的 workflow 里做最小改动：

```text
替换 AI 女主首帧：assets/heroine/keyframes/heroine-dance-mvp-001-keyframe.png
替换目标舞蹈参考视频：assets/heroine/references/target-dance-mvp-001.mp4
如果 workflow 需要姿态图：先用 Video to Pose Map 生成，再接入 Pose to Video
替换 prompt：描述“同目标视频动作和节奏”的 AI 女主舞蹈
其他参数：先保留 workflow 默认值
```

第一条舞蹈 prompt 先明确动作来源：

```text
original adult female virtual influencer, same character identity, follows the target dance pose and rhythm, full body dance, smooth motion, stable face, vertical fashion video
```

如果 workflow 支持 negative prompt，加上：

```text
different face, identity change, broken hands, extra limbs, watermark, text overlay, copied real person face
```

第一轮参数目标：

```text
时长：3-5 秒
动作：尽量贴近目标舞蹈参考视频
主体：单人
镜头：尽量贴近目标视频镜头；不稳定时先固定镜头
分辨率：按 workflow 默认或中等设置
```

点击 `Queue / 队列 / 加入队列`。成功后至少保存：

```text
ComfyUI/output/<本次视频片段>.mp4
assets/heroine/keyframes/<本次首帧>.png
assets/heroine/references/target-dance-mvp-001.mp4
assets/heroine/control/<本次姿态或控制素材>
workflows/heroine-dance-motion-mvp-001.json
```

如果步骤 6 已经保存过 workflow，这里只确认它仍然是本次实际使用的 workflow；如果你中途换过模板，需要重新保存覆盖或另存一个新文件。

如果只生成了 3-5 秒，可以重复生成 2-3 个相近片段。第一条成片不需要复杂剧情，但动作要能看出来自同一段目标舞蹈参考。

## 步骤 9：剪映后期成片

ComfyUI 负责画面素材，剪映负责成片。

在剪映里完成：

```text
新建 9:16 竖屏项目
导入 ComfyUI 输出视频
对照目标舞蹈参考视频的节奏排列 1-3 个片段
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

## 步骤 10：Metadata 留痕

把成片信息写进 metadata：

```markdown
# heroine-dance-mvp-001

- workflow: workflows/heroine-dance-motion-mvp-001.json
- workflow_source: <页面模板 / blueprints / 社区 workflow>
- prompt: original adult female virtual influencer, follows the target dance pose and rhythm...
- target_video: assets/heroine/references/target-dance-mvp-001.mp4
- target_video_source: <目标舞蹈视频来源>
- target_video_allowed_use: <公开视频参考 / 已授权 / 自有素材>
- motion_control: assets/heroine/control/<本次姿态或控制素材>
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

## 步骤 11：发布前检查

导出前逐项看：

```text
画面：9:16 竖屏，主体完整，脸和身材稳定
动作：能看出参考了目标舞蹈视频，没有严重肢体扭曲、手脚穿帮、突然变脸
声音：BGM 清楚，卡点自然，没有未授权声音复制
剪辑：节奏顺，开头 1 秒能留住人，结尾不突兀
字幕：不遮脸、不遮商品、不堆字
封面：主体清楚，能看出女主人设或舞蹈主题
合规：不冒充真人，不保留目标视频里的脸、声音、水印、昵称、个人标识
```

完成后至少留下这些文件：

```text
assets/heroine/keyframes/<本次首帧>.png
assets/heroine/references/target-dance-mvp-001.mp4
assets/heroine/control/<本次姿态或控制素材>
ComfyUI/output/<本次视频片段>.mp4
assets/heroine/exports/videos/heroine-dance-mvp-001.mp4
assets/heroine/exports/covers/heroine-dance-mvp-001-cover.png
assets/heroine/metadata/heroine-dance-mvp-001.md
workflows/heroine-dance-motion-mvp-001.json
```

## 目标舞蹈视频怎么用

目标舞蹈视频不是拿来换脸，而是拆成动作、镜头和节奏：

```text
0.0s-1.0s  全身站姿，轻微摆动
1.0s-2.0s  向镜头走近，右手整理头发
2.0s-3.0s  转身展示裙摆
3.0s-4.0s  回头定格，适合放商品卖点字幕
4.0s-8.0s  重复最稳动作，给 BGM 卡点
```

再翻译成 prompt 或 workflow 参数：

```text
full body fashion pose, the woman slowly turns around, gentle hair movement, smooth camera pan, confident expression
```

如果 workflow 支持姿态、深度、边缘或视频参考控制，就把目标舞蹈视频抽成控制素材；如果不支持，普通 I2V 只能作为兜底，生成结果可能只是“相似氛围”，不能稳定复刻动作。声音只参考节奏，不复制原声。

## 每日最小 SOP

每天只做这个闭环：

```text
1. 选一个目标舞蹈视频，裁出 3-5 秒动作片段。
2. 拆动作、镜头和音乐卡点，写到 metadata。
3. 选一个女主参考图或关键帧。
4. 在 ComfyUI 页面从「模板 / 所有模板 / 生成类型 -> 视频」选择支持动作参考、姿态控制或视频参考的模板。
5. 按页面缺失提示补模型。
6. 输出 1-3 个 3-5 秒 AI 女主舞蹈片段。
7. 剪映按目标视频节奏合成 8-15 秒 9:16 成片。
8. 做发布前检查。
9. 保存输入图、目标视频、控制素材、输出视频、成片、封面、workflow、prompt、BGM 曲名、BGM 来源和 BGM 使用范围。
```

## 复现评审清单

如果你照着本文做完，应该能回答这些问题：

```text
我用了哪张原创女主首帧？
我用了哪段目标舞蹈参考视频？
我是否保存了目标视频动作拆解？
我导入了哪个页面模板或现成 workflow？
页面提示缺了哪些模型，我怎么补齐的？
我是否生成或保存了姿态图 / 动作控制素材？
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

`heroine-i2v-core` 是历史保留的模型包名称，用于以后在 Mac 和服务器复现一组视频生成相关模型。当前 MVP 主线仍然是动作参考 / 姿态控制 / 视频参考 workflow；普通 I2V 只是兜底，不是第一入口。

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
