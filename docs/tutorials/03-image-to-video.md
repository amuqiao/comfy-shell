# 图生视频：让一张图动起来

本篇目标是把一张已经满意的图片变成 3-5 秒短视频。

## 前置条件

建议先完成 [文生图教程](01-text-to-image.md) 或 [图生图教程](02-image-to-image-editing.md)，并准备一张质量稳定的首帧图。模型放置规则统一看 [模型管理](models.md)。

## 你会得到什么

完成后你应该有：

```text
一张首帧图
一个短视频文件
workflows/003-image-to-video.json
```

先做轻微运动，不要一开始追求大幅动作、长镜头或复杂转场。

## 准备模型

图生视频通常需要：

```text
视频 diffusion model     -> ComfyUI/models/diffusion_models/
text encoder             -> ComfyUI/models/text_encoders/
VAE                      -> ComfyUI/models/vae/
LoRA                     -> ComfyUI/models/loras/
```

具体文件名以你选择的 workflow 要求为准。不要把视频模型放进 `checkpoints/`，否则节点可能找不到。

当前 ComfyUI 子模块自带 Wan 2.2 图生视频蓝图：

```text
ComfyUI/blueprints/Image to Video (Wan 2.2).json
```

这个蓝图会提示需要的模型文件。入门时优先按蓝图里的模型清单放置，不要自己猜目录。

## 首帧图片

首帧质量决定视频上限。建议先用前两篇教程生成一张：

- 主体明确。
- 背景不要太乱。
- 没有明显坏手、坏脸或乱码文字。
- 分辨率先保持中等，不要一开始用超大图。

## 跟做步骤

1. 打开 ComfyUI。

2. 导入自带蓝图：

   ```text
   ComfyUI/blueprints/Image to Video (Wan 2.2).json
   ```

3. 用 `Load Image` 加载首帧图。

4. 按工作流要求选择：

   ```text
   diffusion model
   clip vision
   vae
   text encoder 或 prompt 节点
   ```

5. 先用短视频参数：

   ```text
   frames: 33 左右
   resolution: 512x512 或接近这个量级
   motion: 小
   ```

6. prompt 只描述轻微运动：

   ```text
   subtle camera push in, soft wind, cinematic lighting, smooth motion
   ```

7. 点击 `Queue`。

8. 保存视频和 workflow。

## 你刚学会了什么

图生视频不是“让图片随便动”，而是用首帧约束视频模型：

```text
首帧图        决定主体和构图
prompt        决定运动方向和风格
frames        决定时长
分辨率        决定显存和速度
```

新手优先控制时长和分辨率，不要先追求高分辨率长视频。

## 验收标准

这篇教程完成的标准：

- 能从一张图生成短视频。
- 知道视频模型放在 `diffusion_models/`。
- 知道 `frames` 和分辨率会显著影响速度和显存。
- 能保存图生视频 workflow。

## 常见问题

视频抖动大：

降低运动强度，换更稳定的首帧，减少复杂动作描述。

速度很慢：

降低分辨率和帧数。Mac 本机只适合学习流程，正式产出可放到 CUDA 服务器。

找不到模型：

检查模型是否放在工作流要求的目录，尤其是 `diffusion_models/`、`clip_vision/`、`vae/`。

## 进阶玩法

跑通后再学：

- 首帧/尾帧控制。
- 镜头运动 prompt 模板。
- 视频补帧和放大。
- 多段视频拼接。
