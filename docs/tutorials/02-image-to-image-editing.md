# 图生图入门

本篇目标是用一张参考图做二次创作，先学会保留构图并改变风格。

## 前置条件

建议先完成 [文生图教程](01-text-to-image.md)，并准备一张可用参考图。模型放置规则统一看 [模型管理](models.md)。

## 你会得到什么

完成后你应该有：

```text
一张输入参考图
一张二次创作输出图
workflows/002-image-to-image-editing.json
```

## 适合什么时候用

图生图适合这些任务：

- 把照片变成插画、海报或电影感风格。
- 保留构图，改变材质、光照或氛围。
- 为后续图生视频准备一张质量更高的首帧图。

## 准备输入

把参考图拖进 ComfyUI 画布，或者放到：

```text
ComfyUI/input/
```

建议先用主体清楚、构图简单的图片。复杂多人图、文字图、低清图都不适合作为第一张练习图。

## 跟做步骤

1. 打开 ComfyUI。

2. 找一个 `img2img` 或 `image to image` 模板。

3. 用 `Load Image` 选择参考图。

4. 选择 checkpoint。

5. 写正向提示词，描述你想要的新风格：

   ```text
   cinematic portrait, soft rim light, detailed skin, editorial photography, high quality
   ```

6. 调整 denoise：

   ```text
   0.25-0.40   保留原图更多
   0.45-0.65   改动明显，但仍保留构图
   0.70+       更像重新生成
   ```

7. 点击 `Queue`。

8. 保存输出图和 workflow。

## 可选：局部修改是什么

局部修改属于下一阶段能力，通常需要 inpainting workflow 和 mask。入门时只记住：

```text
白色区域 = 要重绘
黑色区域 = 尽量保留
```

先做小范围修改，例如换衣服颜色、改变背景、修复手部，不要一开始重画整张图。

本篇不展开局部重绘的节点连接。先把普通图生图跑通，再在进阶阶段学习 inpainting。

## 你刚学会了什么

图生图的关键不是 prompt，而是三者平衡：

```text
参考图结构
prompt 目标
denoise 改动强度
```

denoise 是最重要的控制旋钮。新手排错时优先调整 denoise。

## 验收标准

这篇教程完成的标准：

- 能加载一张参考图。
- 能改变图片风格。
- 能解释 denoise 变大或变小的效果。
- 能保存图生图 workflow。

## 常见问题

输出和原图几乎一样：

提高 denoise，或者让 prompt 更明确。

输出完全不像原图：

降低 denoise，或者使用 ControlNet/参考图控制类节点。

进阶做局部修改时边缘很脏：

缩小 mask，降低 denoise，或者增加后处理修图步骤。

## 进阶玩法

跑通后再学：

- Inpainting 局部重绘。
- ControlNet Canny/Depth 控制边缘和深度。
- IP-Adapter 或参考图风格迁移。
- Flux Kontext 类编辑工作流。
