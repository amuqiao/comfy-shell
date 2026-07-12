# ComfyUI 业务教程

本目录不再维护“文生图、图生图、图生视频、文生视频”四类基础教程。它们只是业务生产线里的工具能力，单独维护会分散注意力。

## 当前主线

| 文档 | 作用 |
|---|---|
| [AI 女主短视频生产线](ai-heroine-content-pipeline.md) | 从角色资产、变装、热门动作参考到图生视频和带货素材的完整业务流程 |
| [模型管理](models.md) | 说明模型目录、下载边界、`models.sh` 可选清单和 Mac/服务器复用策略 |

## 学习方式

直接从业务闭环开始：

```text
原创 AI 女主身份
-> 角色资产库
-> 变装/试穿关键帧
-> 热门视频动作和镜头参考
-> 图生视频
-> 剪辑发布
-> 复盘沉淀 workflow 和模型包
```

基础能力在实践中自然覆盖：

```text
文生图     用在角色形象、封面、首帧
图生图     用在变装、试穿、局部编辑
图生视频   用在主力短视频生成
文生视频   用在镜头探索和背景素材，不作为主路径
```

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

每次完成一个作品，都保存三类资产：

```text
ComfyUI/output/                     生成图片或视频
workflows/<业务阶段>-<主题>.json    可复现 workflow
assets/heroine/                     女主身份、三视图、表情、变装和首帧素材
```

建议从主线文档的目录结构开始，不再沿用基础教程的 `001-text-to-image.json` 这类命名。
