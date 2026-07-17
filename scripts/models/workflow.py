from __future__ import annotations

import json
import re
import struct
import zlib
from pathlib import Path
from typing import Any

from scripts.models.common import die


def png_text_chunks(raw: bytes) -> dict[str, str]:
    if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
        return {}
    pos = 8
    out: dict[str, str] = {}
    while pos + 8 <= len(raw):
        length = struct.unpack(">I", raw[pos : pos + 4])[0]
        chunk_type = raw[pos + 4 : pos + 8]
        data = raw[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if chunk_type == b"tEXt" and b"\x00" in data:
            key, value = data.split(b"\x00", 1)
            out[key.decode("latin-1", "replace")] = value.decode("utf-8", "replace")
        elif chunk_type == b"zTXt" and b"\x00" in data:
            key, rest = data.split(b"\x00", 1)
            if rest:
                try:
                    out[key.decode("latin-1", "replace")] = zlib.decompress(rest[1:]).decode(
                        "utf-8", "replace"
                    )
                except zlib.error as exc:
                    die(f"invalid compressed PNG metadata: {exc}", 2)
        elif chunk_type == b"iTXt" and b"\x00" in data:
            parts = data.split(b"\x00", 5)
            if len(parts) == 6:
                key = parts[0].decode("utf-8", "replace")
                compressed = parts[1] == b"\x01"
                text = parts[5]
                if compressed:
                    try:
                        text = zlib.decompress(text)
                    except zlib.error as exc:
                        die(f"invalid compressed PNG metadata: {exc}", 2)
                out[key] = text.decode("utf-8", "replace")
    return out


def load_workflow_payload(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        die(f"unable to read workflow file: {exc}", 2)
    try:
        if raw.startswith(b"\x89PNG"):
            chunks = png_text_chunks(raw)
            return {
                "prompt": json.loads(chunks.get("prompt", "{}") or "{}"),
                "workflow": json.loads(chunks.get("workflow", "{}") or "{}"),
            }
        data = json.loads(raw.decode("utf-8"))
    except UnicodeDecodeError as exc:
        die(f"workflow file is not valid UTF-8 JSON or ComfyUI PNG metadata: {exc}", 2)
    except json.JSONDecodeError as exc:
        die(f"invalid workflow JSON metadata: {exc}", 2)
    if isinstance(data, dict) and ("prompt" in data or "workflow" in data):
        return data
    return {"workflow": data, "prompt": data if isinstance(data, dict) else {}}


def suggested_dir(kind: str) -> tuple[str, str]:
    mapping = {
        "checkpoint": "checkpoints",
        "lora": "loras",
        "controlnet": "controlnet",
        "vae": "vae",
        "upscale": "upscale_models",
        "embedding": "embeddings",
    }
    if kind == "node-managed":
        return "", "custom node may manage this model"
    return mapping.get(kind, ""), ""


def inspect_workflow(workflow_file: str) -> int:
    path = Path(workflow_file)
    if not path.is_file():
        die(f"workflow file not found: {workflow_file}", 2)

    payload = load_workflow_payload(path)
    prompt = payload.get("prompt") or {}
    workflow = payload.get("workflow") or {}
    rows: list[tuple[str, str, str, str, str, str, str]] = []

    def add(kind: str, node_id: Any, class_type: str, field: str, value: str) -> None:
        directory, note = suggested_dir(kind)
        rows.append((kind, str(node_id), class_type, field, value, directory, note))

    def sort_key(item: tuple[Any, Any]) -> Any:
        key = str(item[0])
        return int(key) if key.isdigit() else key

    for node_id, node in sorted(prompt.items(), key=sort_key):
        class_type = node.get("class_type", "")
        inputs = node.get("inputs") or {}
        for field, value in inputs.items():
            if not isinstance(value, str):
                continue
            lower = field.lower()
            if field == "ckpt_name":
                add("checkpoint", node_id, class_type, field, value)
            elif field == "lora_name":
                add("lora", node_id, class_type, field, value)
            elif field == "control_net_name":
                add("controlnet", node_id, class_type, field, value)
            elif field == "vae_name":
                add("vae", node_id, class_type, field, value)
            elif class_type == "UpscaleModelLoader" and field == "model_name":
                add("upscale", node_id, class_type, field, value)
            elif class_type.startswith("WD14Tagger") and field == "model":
                add("node-managed", node_id, class_type, field, value)
            elif lower == "text":
                for name in re.findall(r"embedding:([^,\s]+)", value):
                    add("embedding", node_id, class_type, field, name)

    if not rows and isinstance(workflow, dict) and workflow.get("nodes"):
        for node in workflow.get("nodes") or []:
            class_type = node.get("type", "")
            for value in node.get("widgets_values") or []:
                if isinstance(value, str) and re.search(r"\.(safetensors|ckpt|pth|pt|bin)$", value, re.I):
                    add("unknown", node.get("id", ""), class_type, "widget", value)

    print("KIND\tNODE\tCLASS\tFIELD\tVALUE\tSUGGESTED_DIR\tNOTE")
    for row in rows:
        print("\t".join(row))
    return 0
