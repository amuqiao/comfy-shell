# 模型 catalog 维护记录

`configs/models/catalog.yaml` 是机器可读的模型清单；本文只记录人工判断过程和暂不进入 bundle 的线索。

## 数据结构约定

每个模型同时记录两个对象：

```yaml
source:
  platform: civitai | huggingface | liblib | unknown
  page_url: ...
  creator: ...
  model_id: ...
  version_id: ...

download:
  mode: auto | manual | blocked
  method: civitai | huggingface | browser
  sha256: ...
  size_bytes: ...
  reason: ...
```

- `source` 说明模型来自哪里。
- `download` 说明脚本能不能自动下载，以及如何下载。
- `auto` 必须有可信 `sha256`。
- `manual` 表示用户需要打开页面或作者说明自己下载。
- `blocked` 表示已知道下载线索，但 catalog 还缺少自动下载所需的可靠信息。

## retro-anime-photo-core

当前 PNG workflow 引用的文件：

```text
checkpoints/isabelia_v10.safetensors
loras/80'sFusion.safetensors
loras/Retro_Anime-000002.safetensors
controlnet/control_v11p_sd15_openpose.pth
controlnet/control_v11f1p_sd15_depth.pth
controlnet/control_v11p_sd15_lineart.pth
vae/kl-f8-anime2.ckpt
upscale_models/4xUltrasharp_4xUltrasharpV10.pth
embeddings/EasyNegative.safetensors
```

已确认可自动下载：

| file | source | method |
|---|---|---|
| `isabelia_v10.safetensors` | Civitai model `189416`, version `212741` | `civitai` |
| `80'sFusion.safetensors` | Civitai model `112241`, version `123524` | `civitai` |
| `Retro_Anime-000002.safetensors` | Civitai model `211819`, version `238615` | `civitai` |
| `control_v11p_sd15_openpose.pth` | Hugging Face `lllyasviel/ControlNet-v1-1` | `huggingface` |
| `control_v11f1p_sd15_depth.pth` | Hugging Face `lllyasviel/ControlNet-v1-1` | `huggingface` |
| `control_v11p_sd15_lineart.pth` | Hugging Face `lllyasviel/ControlNet-v1-1` | `huggingface` |
| `EasyNegative.safetensors` | Hugging Face dataset `gsdf/EasyNegative` | `huggingface` |

仍需人工确认：

| file | reason |
|---|---|
| `kl-f8-anime2.ckpt` | workflow 只有文件名，尚未确认唯一可信来源。 |
| `4xUltrasharp_4xUltrasharpV10.pth` | 常见 `4x-UltraSharp.pth` 可能是同类模型，但未确认和 workflow 文件等价，不自动重命名。 |

## 视频课程提到但当前 PNG workflow 未引用

这些模型可能用于同一期课程的其他 workflow，但当前 `retro-anime-photo-core` PNG 没有引用对应文件名，所以不作为必需模型写入 bundle：

| model | source |
|---|---|
| AWPaiting / AWPainting | `https://civitai.com/models/84476/awpainting`；`https://liblib.art/modelinfo/1fd281cf6bcf01b95033c03b471d8fd8` |
| majicMIX lux | `https://civitai.com/models/56967/majicmix-lux`；`https://liblib.art/modelinfo/c6cfead266b9b38cd8257655ca76dbc2` |
