# ComfyUI Tutorials

这组教程的目标不是讲完所有节点，而是让你按步骤完成作品，并在过程中建立 ComfyUI 的基本使用模型。

## 文档边界

这组教程默认你已经能通过本仓库脚本启动 ComfyUI。安装、环境、启动和停止请看项目 [README](../../README.md)。

脚本职责边界请看 [scripts 维护规范](../../scripts/README.md)。当前脚本不会自动下载模型，也不会自动安装第三方 `custom_nodes`。

## 学习方式

先按作品目标学习，再回头理解节点。每篇教程都遵循同一个节奏：

```text
准备模型 -> 打开或搭建工作流 -> 跑出结果 -> 保存作品和 workflow -> 再做一个进阶变化
```

不要一开始追求最复杂的模型和最长的视频。先用小目标稳定跑通，再逐步替换模型、提高分辨率、增加控制节点。

## 推荐顺序

| 顺序 | 教程 | 目标作品 | 难度 |
|---|---|---|---|
| 1 | [文生图：做一张海报或头像](01-text-to-image.md) | 一张可展示图片 | 入门 |
| 2 | [图生图入门](02-image-to-image-editing.md) | 一张参考图的二次创作 | 入门 |
| 3 | [图生视频：让一张图动起来](03-image-to-video.md) | 一个 3-5 秒短片 | 进阶 |
| 4 | [文生视频：从文字生成短片](04-text-to-video.md) | 一个短视频片段 | 进阶 |

模型目录、命名和迁移策略单独看 [模型管理](models.md)。
页面下载是新手主路径；`scripts/models.sh` 是可选的工程化模型清单入口。

## 开始前检查

如果是第一次在这台机器运行，按根 [README](../../README.md) 的本机启动流程先准备环境：

```bash
./scripts/env.sh use macos-mps
./scripts/check_env.sh --no-network
./scripts/dev.sh bootstrap
./scripts/dev.sh start
./scripts/dev.sh status
```

如果已经 bootstrap 过，日常只需要：

```bash
./scripts/nodes.sh status
./scripts/dev.sh start
./scripts/dev.sh status
```

浏览器打开：

```text
http://127.0.0.1:8188
```

`status` 里看到下面结果即可继续：

```text
READY      system_stats       ok
```

## 保存规则

每次完成一个作品，都保存两样东西：

```text
ComfyUI/output/                 生成图片或视频
workflows/<编号>-<主题>.json    可复现 workflow
```

建议命名：

```text
workflows/001-text-to-image.json
workflows/002-image-to-image-editing.json
workflows/003-image-to-video.json
workflows/004-text-to-video.json
```

如果还没有 `workflows/` 目录，可以创建：

```bash
mkdir -p workflows
```

## 作品目标

第一周只追求完成这三类作品：

1. 一张头像或海报图。
2. 一张基于参考图的风格化图片。
3. 一个 3-5 秒图生视频短片。

完成后再学习 LoRA、ControlNet、批量出图、API 自动化和服务器部署。
