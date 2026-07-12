# ComfyUI 业务教程

本目录维护 AI 女主短视频业务主线：从 ComfyUI 页面模板或现成 workflow 出发，先产出第一条 8-15 秒可发布竖屏成片。

## 先看什么

| 文档 | 作用 |
|---|---|
| [AI 女主短视频 MVP 生产线](ai-heroine-content-pipeline.md) | 打开页面模板或现成 workflow，补缺模型，产出第一条可发布成片 |
| [模型管理](models.md) | 说明页面缺模型怎么补，以及 `models.sh` 为什么只是跑通后的复现工具 |

## 当前心智模型

目标不是学习节点，而是让业务先运转起来：

```text
可用素材
-> 打开 ComfyUI「模板 / 所有模板 / Popular / 使用案例 / 生成类型 -> 视频」/ blueprints / 社区 workflow
-> 页面提示缺模型就补模型
-> 只替换输入图、prompt 和少量参数
-> 先生成 3-5 秒画面片段
-> 剪映合成 8-15 秒竖屏成片
-> 保存 workflow、成片和 metadata
-> 跑通后再考虑 models.sh、女主资产库、试穿、LoRA 和批量化
```

不要从这些事情开始：

```text
从零搭节点
一开始研究模型包
一开始写 catalog
先训练 LoRA
先追求完美一致性
先下载轻量玩具模型
```

## 今日目标

今天只追求一个结果：

```text
用一个原创 AI 女主参考图
在 ComfyUI 页面从「模板 / 所有模板 / Popular / 使用案例 / 生成类型 -> 视频」选择模板，或导入现成图生视频 workflow
按页面缺失提示补模型
生成 1-3 个 3-5 秒画面片段
剪映加 BGM、字幕、封面
导出 8-15 秒 9:16 竖屏成片
保存 workflow、prompt、输入图、输出视频、成片、封面、BGM 来源和 BGM 使用范围
```

跑通之后，再扩展：

```text
女主身份资产库
变装关键帧
服装试穿
热门动作参考
日更 SOP
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

第一次实验前准备目录：

```bash
mkdir -p assets/heroine/inputs assets/heroine/keyframes assets/heroine/exports/videos assets/heroine/exports/covers assets/heroine/metadata workflows
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

每次完成一个实验，都保存四类资产：

```text
assets/heroine/inputs/            你提供的输入素材
assets/heroine/keyframes/         女主关键帧、变装前后图、试穿图
ComfyUI/output/                   生成图片或视频
assets/heroine/exports/videos/    最终成片
assets/heroine/exports/covers/    封面图
assets/heroine/metadata/          workflow、prompt、模型、BGM 来源和 BGM 使用范围记录
workflows/<业务阶段>-<主题>.json  可复现 workflow
```

workflow 直接按业务阶段命名。
