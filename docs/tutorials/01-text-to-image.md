# 文生图：做一张海报或头像

本篇目标是用 ComfyUI 从一句提示词生成一张可展示图片，并学会保存可复现的 workflow。

## 前置条件

先完成 [教程入口](README.md) 的启动检查。模型放置规则统一看 [模型管理](models.md)。

## 你会得到什么

完成后你应该有：

```text
ComfyUI/output/ 中的一张图片
workflows/001-text-to-image.json
```

建议先做头像、海报、封面图，不要一开始做复杂多人构图。

## 准备模型

入门优先选一种路线：

| 路线 | 推荐模型类型 | 放置目录 | 适合场景 |
|---|---|---|---|
| SDXL | checkpoint | `ComfyUI/models/checkpoints/` | 稳定、资料多、适合入门 |
| Flux FP8 单文件 | checkpoint | `ComfyUI/models/checkpoints/` | 画质好，节点更简单 |

模型文件放好后，重启 ComfyUI 或在界面刷新模型列表。

如果想用可选脚本检查或下载教程标准模型包：

```bash
./scripts/models.sh plan sdxl-basic
./scripts/models.sh status sdxl-basic
HF_ENDPOINT=https://hf-mirror.com ./scripts/models.sh download sdxl-basic
```

这不是必做步骤。你也可以在页面里通过 ComfyUI-Manager 或工作流提示下载模型。

## 跟做步骤

1. 打开 ComfyUI：

   ```text
   http://127.0.0.1:8188
   ```

2. 使用内置模板或默认文生图 workflow。

3. 在 `Load Checkpoint` 节点选择你的 checkpoint。

4. 正向提示词先写清主体、风格、构图：

   ```text
   a clean editorial poster of a futuristic city at sunrise, cinematic lighting, detailed, high quality
   ```

5. 反向提示词先保持简单：

   ```text
   low quality, blurry, distorted, bad anatomy, text, watermark
   ```

6. 先用保守参数：

   ```text
   width: 1024
   height: 1024
   steps: 20-30
   cfg: 5-7
   seed: random 或固定一个 seed
   ```

7. 点击 `Queue`，等待出图。

8. 生成满意后导出 workflow：

   ```text
   Save / Export workflow -> workflows/001-text-to-image.json
   ```

## 你刚学会了什么

最少需要理解这几个节点：

```text
Load Checkpoint      选择模型
CLIP Text Encode     把 prompt 编成模型能理解的条件
KSampler             真正生成潜空间图像
VAE Decode           把潜空间结果变成图片
Save Image           保存输出
```

先不要急着改 sampler。先通过 prompt、seed、steps、cfg、分辨率观察变化。

## 验收标准

这篇教程完成的标准：

- 能稳定生成图片。
- 知道 checkpoint 文件放在哪里。
- 知道怎么保存 workflow。
- 能复用同一个 workflow 改 prompt 再出图。

## 常见问题

`Load Checkpoint` 里看不到模型：

检查模型是否放在：

```text
ComfyUI/models/checkpoints/
```

放好后重启 ComfyUI。

图片很慢：

先把分辨率降到 `768x768` 或 `512x512`，确认流程能跑通，再提高分辨率。

输出不稳定：

固定 seed，每次只改一个参数。不要同时改 prompt、sampler、steps、cfg。

## 进阶玩法

入门跑通后再尝试：

- 用 LoRA 固定画风。
- 批量生成 10 张图后挑选。
- 用 ControlNet 控制姿势或构图。
- 保存多个 workflow，建立自己的常用模板库。
