# AI 女主短视频生产线

本文目标是搭一条可复用的 AI 女主内容生产线：先建立原创女主身份，再围绕变装、试穿、热门动作参考和图生视频持续出片。

## 这篇文档解决什么

它不讲 ComfyUI 基础教程，不按“文生图、图生图、文生视频、图生视频”拆课。那些能力会在业务流程中自然用到。

本文负责：

- 设计一个稳定可识别的原创 AI 女主。
- 建立角色资产库，支持换装、变装和试穿。
- 把热门短视频拆成动作、镜头和节奏参考。
- 用图片生成、图片编辑、图生视频组合成日更工作流。
- 约束模型、workflow、素材和输出的沉淀方式。

本文不负责：

- 冒充真实博主或复刻真人身份。
- 未授权换脸、声音克隆或把真人转成敏感内容。
- 规避平台审核或制作违规内容。

## 核心判断

不要做一个巨大 workflow。稳定账号要拆成多个业务 workflow：

```text
女主身份资产
-> 角色一致性
-> 变装/试穿关键帧
-> 热门动作参考
-> 图生视频
-> 剪辑发布
```

长期一致的是：

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
情绪
风格尺度
```

所以目标不是固定穿搭，而是固定“观众能认出来这是同一个 AI 女主”。

## 内容边界

可以参考真实热门视频的：

```text
动作节奏
镜头角度
构图
转场
服装品类
拍摄脚本
```

不要直接复刻真实博主的：

```text
脸
身份
声音
水印
个人标识
未授权原片内容
```

正确做法是：热门视频作为动作和镜头参考，主角必须是原创 AI 女主。

## 资产目录

先建立一个稳定目录，不要把所有图片扔进 `output/`：

```text
assets/heroine/
  identity/
    face-front.png
    half-body.png
    full-body-front.png
    full-body-side.png
    full-body-back.png
  expressions/
    smile.png
    cool.png
    sweet.png
  outfits/
    base/
    dress/
    streetwear/
    product-try-on/
  keyframes/
    dance/
    fashion/
    product/
  references/
    motion/
    camera/
  exports/
    covers/
    videos/
workflows/
  heroine-identity.json
  heroine-image-edit.json
  heroine-i2v-dance.json
  heroine-fashion-tryon.json
```

第一阶段必须先产出 `identity/`，否则后续每天都会像换了一个人。

## 阶段 1：建立原创女主身份

目标是生成一组角色标准图，不是直接做视频。

建议产物：

```text
正脸头像
半身标准照
全身正面
全身侧面
全身背面
3-5 个表情
2-3 套基础服装
```

提示词要稳定描述身份，而不是只描述衣服：

```text
an original young adult female virtual influencer, recognizable face, elegant confident temperament, consistent body proportion, clean studio lighting, high quality portrait
```

衣服单独描述，避免把穿搭写进身份核心：

```text
outfit: white fitted top and simple skirt
outfit: black evening dress
outfit: casual streetwear jacket
```

验收标准：

- 换衣服后仍像同一个人。
- 正脸、半身、全身之间脸和身材比例一致。
- 没有明显坏手、坏脸、畸形肢体。
- 能选出 3-5 张作为长期参考图。

## 阶段 2：角色一致性工作流

短期用参考图控制一致性：

```text
女主标准图
-> 参考图/identity 节点
-> prompt 描述新场景和穿搭
-> 输出新关键帧
```

长期建议训练或沉淀女主专属 LoRA：

```text
identity 标准图
多角度图
不同表情
不同服装
统一命名和标注
```

不建议一开始训练 LoRA。先用参考图方式跑通 20-50 张稳定素材，再筛选高质量图做训练集。

## 阶段 3：变装和试穿关键帧

变装视频不要直接从文字生成整段视频。先做关键帧：

```text
变装前关键帧
变装后关键帧
商品试穿图
封面图
```

女装带货素材至少需要：

```text
商品图
女主标准图
试穿正面图
试穿侧面图
细节展示图
短视频首帧
```

验收标准：

- 商品主体清楚。
- 女主身份没有漂移。
- 衣服形态和商品图一致，不要严重幻觉。
- 画面可以直接作为短视频首帧或封面。

## 阶段 4：热门视频参考拆解

不要把热门视频当“换脸目标”，而是拆解成参考数据：

```text
动作：转身、抬手、走近镜头、摆裙、回头
镜头：半身、全身、低机位、推近、横移
节奏：几秒一个动作点，哪里变装，哪里卡点
场景：街拍、试衣间、室内棚拍、舞台
```

建议记录成文字脚本：

```text
0.0s-1.0s  全身站姿，轻微摆动
1.0s-2.0s  向镜头走近，右手整理头发
2.0s-3.0s  转身展示裙摆
3.0s-4.0s  回头定格，适合放商品卖点字幕
```

这样你是在复用“动作语言”，不是复制真人。

## 阶段 5：图生视频主工作流

主力视频路径应该是图生视频：

```text
女主关键帧
-> 图生视频 workflow
-> 轻动作 prompt
-> 短视频输出
-> 剪辑、配乐、字幕
```

首帧质量决定视频上限。不要拿不稳定的图直接做视频。

建议先做短片段：

```text
3-5 秒
单主体
轻动作
低到中等分辨率
一次只改一个变量
```

常见动作 prompt：

```text
subtle camera push in, the woman turns slightly, smooth motion, fashion video, soft studio lighting
```

```text
full body fashion walk, gentle hair movement, confident pose, smooth camera pan
```

## 阶段 6：剪辑发布

ComfyUI 负责生成素材，不负责完整运营。发布前还需要剪辑：

```text
裁切竖屏 9:16
节奏卡点
字幕和卖点
封面
音乐
平台标题
```

每日最小 SOP：

```text
1. 选一个热门视频，拆动作和镜头。
2. 选一套女主穿搭或商品。
3. 生成 2-4 张关键帧。
4. 选 1 张最稳的做图生视频。
5. 输出 3-5 秒片段。
6. 剪辑成 8-15 秒竖屏视频。
7. 保存 workflow、prompt、模型和成片。
```

## 模型策略

不要为了“入门轻量”下载过时模型。模型几个 GB 是正常成本，应该下载能长期服务业务的主线模型。

当前已落地到 `configs/models/catalog.yaml` 的模型包：

```text
heroine-i2v-core         图生视频主线
heroine-t2v-explore      文生视频探索，不作为主生产路径
```

后续规划沉淀，但当前还没有标准化 catalog 条目的模型包：

```text
heroine-image-core       女主身份图、封面、首帧
heroine-image-edit       变装、试穿、局部编辑
```

查看模型计划：

```bash
./scripts/models.sh list
./scripts/models.sh plan heroine-i2v-core
```

显式下载时再执行：

```bash
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download heroine-i2v-core
```

`models.sh` 是可选工程化入口。页面里按 workflow 提示下载也可以，但常用模型最后应该沉淀进 `configs/models/catalog.yaml`。

## 工作流清单

建议逐步沉淀这些 workflow：

```text
workflows/heroine-identity.json
workflows/heroine-image-edit.json
workflows/heroine-fashion-tryon.json
workflows/heroine-i2v-dance.json
workflows/heroine-i2v-product.json
```

不要把所有节点塞进一个 workflow。每个 workflow 只解决一个稳定产出目标。

## 第一周目标

第一周不要追求日更，先追求资产稳定：

```text
第 1 天：生成 20 张女主候选，选 1 个身份方向
第 2 天：生成三视图、半身、全身、表情
第 3 天：测试 3 套穿搭，确认变装后身份稳定
第 4 天：选一个热门动作参考，生成首帧
第 5 天：跑通 3-5 秒图生视频
第 6 天：剪辑成第一条竖屏视频
第 7 天：整理 workflow、prompt、模型和失败样例
```

完成第一周后，再考虑 LoRA、批量化、试穿链路和服务器加速。
