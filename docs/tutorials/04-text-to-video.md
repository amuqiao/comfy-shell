# 文生视频：从文字生成短片

本篇目标是直接从 prompt 生成一个短视频片段。它比文生图和图生视频更吃模型、显存和时间，建议放在第四篇学习。

## 前置条件

建议先完成 [图生视频教程](03-image-to-video.md)。模型放置规则统一看 [模型管理](models.md)。

## 你会得到什么

完成后你应该有：

```text
一个短视频文件
workflows/004-text-to-video.json
```

## 适合什么时候学

先满足这些条件再做文生视频：

- 已经能稳定跑文生图。
- 已经知道模型目录怎么放。
- 已经跑通过至少一个图生视频工作流。
- 能接受一次生成等待较久。

## 准备模型

文生视频通常需要：

```text
视频 diffusion model   -> ComfyUI/models/diffusion_models/
text encoder           -> ComfyUI/models/text_encoders/
VAE                    -> ComfyUI/models/vae/
LoRA                   -> ComfyUI/models/loras/
```

新手优先选择较小的视频模型或量化版本。不要一开始下载最大模型。

当前 ComfyUI 子模块自带 Wan 2.2 文生视频蓝图：

```text
ComfyUI/blueprints/Text to Video (Wan 2.2).json
```

这个蓝图会提示需要的模型文件。入门时优先按蓝图里的模型清单放置，不要自己猜目录。

## 跟做步骤

1. 打开 ComfyUI。

2. 导入自带蓝图：

   ```text
   ComfyUI/blueprints/Text to Video (Wan 2.2).json
   ```

3. 按工作流要求选择 diffusion model、text encoder、VAE。

4. 先用短 prompt，描述主体、场景、运动：

   ```text
   a cinematic shot of a small robot walking through a rainy neon street, slow camera pan, smooth motion
   ```

5. 先用低风险参数：

   ```text
   frames: 33 左右
   resolution: 512x512 或接近这个量级
   steps: 按 workflow 默认值
   ```

6. 点击 `Queue`。

7. 保存视频和 workflow。

## 你刚学会了什么

文生视频比文生图多了两个主要难点：

```text
时间一致性     每一帧都要连贯
资源消耗       模型更大、计算更久、显存压力更高
```

因此新手要先控制变量：短视频、小分辨率、简单 prompt。

## 验收标准

这篇教程完成的标准：

- 能从文字生成一个短视频。
- 知道文生视频模型不一定放在 `checkpoints/`。
- 能解释为什么帧数和分辨率会明显影响速度。
- 能保存文生视频 workflow。

## 常见问题

生成时间太长：

减少帧数和分辨率。Mac 本机用于学习，服务器用于正式产出。

画面不连贯：

缩短 prompt，降低动作复杂度，减少主体数量。

显存不够：

换更小模型或量化版本，降低分辨率和帧数。

## 进阶玩法

跑通后再学：

- 镜头语言 prompt 模板。
- 先文生图生成关键帧，再图生视频。
- 视频放大、补帧和后期剪辑。
- 把 workflow 导出为 API 格式做批量任务。
