# ComfyUI 业务教程

本目录维护 AI 女主短视频业务主线：先生成原创 AI 女主身份图和视频首帧，再用一段目标舞蹈参考视频驱动动作，产出第一条 8-15 秒可发布竖屏成片。

## 先看什么

| 文档 | 作用 |
|---|---|
| [AI 女主短视频 MVP 生产线](ai-heroine-content-pipeline.md) | 打开页面模板或现成 workflow，补缺模型，产出第一条可发布成片 |
| [模型管理](models.md) | 说明页面缺模型怎么补，以及 `models.sh` 为什么只是跑通后的复现工具 |

## 当前心智模型

目标不是学习节点，而是让业务先运转起来：

```text
原创 AI 女主身份图
-> 视频首帧
-> 目标舞蹈参考视频
-> 在 ComfyUI「模板 / 所有模板」里优先找 Popular、使用案例、生成类型 -> 视频
-> 优先选择动作参考、姿态控制、视频参考 workflow
-> 找不到合适模板时，用 blueprints 或社区 workflow 兜底
-> 页面提示缺模型就补模型
-> 替换 AI 女主首帧、目标视频或姿态控制素材
-> 先生成 3-5 秒 AI 女主舞蹈片段
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
生成或准备一个原创 AI 女主身份图
生成一张适合做视频生成输入的视频首帧
准备一段 3-5 秒目标舞蹈参考视频
拆出目标视频的动作、镜头和节奏
在 ComfyUI 页面从「模板 / 所有模板」里找 Popular、使用案例、生成类型 -> 视频
优先找动作参考、姿态控制、视频参考 workflow
找不到合适模板时，导入仓库 blueprints 或现成 workflow 兜底
按页面缺失提示补模型
生成 1-3 个 3-5 秒 AI 女主舞蹈片段
剪映加 BGM、字幕、封面
导出 8-15 秒 9:16 竖屏成片
保存 workflow、prompt、输入图、目标视频、目标视频来源、实际控制素材、输出视频、成片、封面、BGM 来源和 BGM 使用范围
```

今天先不要做：

```text
完整女主资产库
多套变装和试穿
复杂动作控制
角色 LoRA 训练
批量自动化
```

## 开始前检查

如果是第一次在这台机器运行，按根 [README](../../README.md) 的本机启动流程先准备环境：

```bash
cp configs/profiles/macos-mps.env.example .env
./scripts/check_env.sh --no-network
./scripts/local.sh bootstrap
./scripts/local.sh start
./scripts/local.sh status
```

如果已经 bootstrap 过，日常只需要：

```bash
./scripts/nodes.sh status
./scripts/local.sh start
./scripts/local.sh status
```

第一次实验前准备目录：

```bash
mkdir -p assets/heroine/inputs assets/heroine/references assets/heroine/identity assets/heroine/keyframes assets/heroine/control assets/heroine/exports/videos assets/heroine/exports/covers assets/heroine/metadata workflows
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

每次完成一个实验，都保存这些资产：

```text
assets/heroine/inputs/            你提供的输入素材
assets/heroine/references/        目标舞蹈参考视频
assets/heroine/identity/          女主身份图：正脸、半身、全身正面
assets/heroine/keyframes/         视频首帧和本次关键帧
assets/heroine/control/           姿态图、深度图、边缘图等动作控制素材
ComfyUI/output/                   生成图片或视频
assets/heroine/exports/videos/    最终成片
assets/heroine/exports/covers/    封面图
assets/heroine/metadata/          workflow、prompt、模型、目标视频来源、实际控制素材、BGM 来源和 BGM 使用范围记录
workflows/<业务阶段>-<主题>.json  可复现 workflow
```

workflow 直接按业务阶段命名。
