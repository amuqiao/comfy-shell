#!/usr/bin/env python3
"""models.sh implementation.

This module is intentionally invoked through scripts/models.sh. It only manages
model catalog assets for the comfy-shell wrapper; it does not bootstrap or run
ComfyUI itself.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request
from urllib.parse import urlparse
import zlib
from pathlib import Path
from typing import Any


ROOT_DIR = Path(os.environ.get("ROOT_DIR", Path(__file__).resolve().parents[2]))
DEFAULT_CONFIG_FILE = ROOT_DIR / ".env"
CATALOG_FILE = Path(os.environ.get("CATALOG_FILE", ROOT_DIR / "configs/models/catalog.yaml"))
HF_CLI = os.environ.get("HF_CLI", "hf")
VALID_DOWNLOAD_MODES = {"auto", "manual", "blocked"}
VALID_AUTO_METHODS = {"huggingface", "civitai"}
VALID_URL_SCHEMES = {"http", "https", "file"}


class CliError(Exception):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


def die(message: str, code: int = 1) -> None:
    raise CliError(message, code)


def section(name: str) -> None:
    print(f"\n===== {name} =====")


def event(kind: str, name: str, detail: str = "") -> None:
    print(f"{kind:<18} {name:<24} {detail}")


def env_value_from(key: str, file_path: Path) -> str:
    if not file_path.is_file():
        return ""
    value = ""
    pattern = re.compile(rf"^\s*(?:export\s+)?{re.escape(key)}\s*=")
    for raw_line in file_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or not pattern.match(raw_line):
            continue
        parsed = re.sub(r"^\s*(?:export\s+)?[^=]*=", "", raw_line)
        parsed = re.sub(r"\s+#.*$", "", parsed).strip()
        if (parsed.startswith('"') and parsed.endswith('"')) or (
            parsed.startswith("'") and parsed.endswith("'")
        ):
            parsed = parsed[1:-1]
        if parsed:
            value = parsed
    return value


def config_value(key: str, config_file: Path) -> str:
    return os.environ.get(key) or env_value_from(key, config_file)


def repo_path(path: str) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    return ROOT_DIR / candidate


def parse_profile_args(command_name: str, argv: list[str]) -> tuple[list[str], Path]:
    args: list[str] = []
    config_file = DEFAULT_CONFIG_FILE
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--profile":
            if index + 1 >= len(argv):
                die("--profile requires a file", 2)
            config_file = repo_path(argv[index + 1])
            index += 2
        elif arg.startswith("--profile="):
            config_file = repo_path(arg.split("=", 1)[1])
            index += 1
        elif arg.startswith("-"):
            die(f"{command_name} unknown option: {arg}", 2)
        else:
            args.append(arg)
            index += 1
    return args, config_file


def require_config_file(config_file: Path) -> None:
    if not config_file.is_file():
        die(f"config file not found: {config_file}", 2)


def model_root_from_config(config_file: Path) -> Path:
    require_config_file(config_file)
    configured = config_value("COMFY_MODEL_ROOT", config_file)
    if not configured:
        die(f"missing required config: COMFY_MODEL_ROOT in process environment or {config_file}", 2)
    return repo_path(configured)


def require_catalog() -> None:
    if not CATALOG_FILE.is_file():
        die(f"catalog not found: {CATALOG_FILE}", 2)


def load_yaml_module():
    try:
        import yaml  # type: ignore[import-not-found]
    except Exception as exc:  # pragma: no cover - exact import error varies by host
        die(
            f"PyYAML not available in {sys.executable}; run ./scripts/local.sh bootstrap first",
            2,
        )
        raise AssertionError from exc
    return yaml


def require_dict(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        die(f"invalid catalog: {label} must be a mapping", 2)
    return value


def require_str(mapping: dict[str, Any], key: str, label: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        die(f"invalid catalog: {label}.{key} is required", 2)
    return value


def validate_size_bytes(download: dict[str, Any], label: str) -> None:
    if "size_bytes" not in download:
        return
    value = download["size_bytes"]
    if not isinstance(value, int) or value <= 0:
        die(f"invalid catalog: {label}.download.size_bytes must be a positive integer", 2)


def validate_download_url(url: str, label: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in VALID_URL_SCHEMES:
        die(
            f"invalid catalog: {label}.download.url must use http, https, or file scheme",
            2,
        )
    if parsed.scheme in {"http", "https"} and not parsed.netloc:
        die(f"invalid catalog: {label}.download.url is missing host", 2)
    if parsed.scheme == "file" and not parsed.path:
        die(f"invalid catalog: {label}.download.url is missing file path", 2)


def require_model_str(model: dict[str, Any], key: str, label: str) -> str:
    value = model.get(key)
    if not isinstance(value, str) or not value:
        die(f"invalid catalog: {label}.{key} is required", 2)
    return value


def model_label(bundle_name: str, model: dict[str, Any], index: int) -> str:
    return f"bundles.{bundle_name}.models[{index}]({model.get('id', '<missing-id>')})"


def validate_model(bundle_name: str, model: dict[str, Any], index: int) -> None:
    label = model_label(bundle_name, model, index)
    require_model_str(model, "id", label)
    require_model_str(model, "directory", label)
    require_model_str(model, "filename", label)
    source = require_dict(model.get("source"), f"{label}.source")
    download = require_dict(model.get("download"), f"{label}.download")
    require_str(source, "platform", f"{label}.source")
    validate_size_bytes(download, label)
    mode = require_str(download, "mode", f"{label}.download")
    if mode not in VALID_DOWNLOAD_MODES:
        die(f"invalid catalog: {label}.download.mode must be one of auto, manual, blocked", 2)
    if mode == "auto":
        method = require_str(download, "method", f"{label}.download")
        if method not in VALID_AUTO_METHODS:
            die(f"invalid catalog: unsupported auto download method for {model['id']}: {method}", 2)
        require_str(download, "sha256", f"{label}.download")
        if method == "huggingface":
            require_str(download, "repo_type", f"{label}.download")
            require_str(download, "repo", f"{label}.download")
            remote_path = require_str(download, "path", f"{label}.download")
            if Path(remote_path).name != str(model["filename"]):
                die(
                    f"invalid catalog: {label}.download.path basename must match filename: "
                    f"{Path(remote_path).name} != {model['filename']}",
                    2,
                )
        elif method == "civitai":
            validate_download_url(require_str(download, "url", f"{label}.download"), label)
    elif mode in {"manual", "blocked"}:
        require_str(download, "reason", f"{label}.download")


def validate_catalog(data: dict[str, Any]) -> None:
    if data.get("version") != 2:
        die("invalid catalog: version must be 2; old catalog schema is not supported", 2)
    bundles = require_dict(data.get("bundles"), "bundles")
    for bundle_name, bundle in bundles.items():
        if not isinstance(bundle_name, str) or not bundle_name:
            die("invalid catalog: bundle name must be a non-empty string", 2)
        bundle_map = require_dict(bundle, f"bundles.{bundle_name}")
        models = bundle_map.get("models")
        if not isinstance(models, list):
            die(f"invalid catalog: bundles.{bundle_name}.models must be a list", 2)
        for index, model in enumerate(models):
            validate_model(bundle_name, require_dict(model, f"bundles.{bundle_name}.models[{index}]"), index)


def load_catalog() -> dict[str, Any]:
    require_catalog()
    yaml = load_yaml_module()
    with CATALOG_FILE.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    data = require_dict(data, "catalog")
    validate_catalog(data)
    return data


def bundle_items(data: dict[str, Any], bundle_name: str) -> list[tuple[str, dict[str, Any]]]:
    bundles = data.get("bundles") or {}
    if bundle_name:
        if bundle_name not in bundles:
            die(f"unknown bundle: {bundle_name}", 2)
        return [(bundle_name, bundles[bundle_name])]
    return sorted(bundles.items())


def source_info(model: dict[str, Any]) -> dict[str, Any]:
    return require_dict(model.get("source"), f"{model['id']}.source")


def download_info(model: dict[str, Any]) -> dict[str, Any]:
    return require_dict(model.get("download"), f"{model['id']}.download")


def download_mode(model: dict[str, Any]) -> str:
    return str(download_info(model)["mode"])


def download_method(model: dict[str, Any]) -> str:
    return str(download_info(model).get("method", ""))


def model_path(model_root: Path, model: dict[str, Any]) -> Path:
    return model_root / model["directory"] / model["filename"]


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_matches(path: Path, expected_sha: str, expected_size: Any) -> tuple[bool, str]:
    if expected_size is not None and path.stat().st_size != int(expected_size):
        return False, f"size mismatch: {path.stat().st_size} != {expected_size}"
    actual_sha = file_sha256(path)
    if actual_sha.lower() != expected_sha.lower():
        return False, f"sha256 mismatch: {actual_sha}"
    return True, f"sha256={actual_sha}"


def model_state(model_root: Path, model: dict[str, Any], strict: bool = False) -> tuple[str, Path, str, bool]:
    path = model_path(model_root, model)
    source = source_info(model)
    download = download_info(model)
    mode = str(download["mode"])
    expected_sha = str(download.get("sha256") or "")
    expected_size = download.get("size_bytes")
    reason = str(download.get("reason") or "")

    if mode == "blocked":
        suffix = "present" if path.is_file() and path.stat().st_size > 0 else "missing"
        return ("BLOCKED", path, f"{suffix}; {reason}", False)

    if not path.is_file() or path.stat().st_size <= 0:
        if mode == "manual":
            return ("MANUAL", path, f"missing; {reason}", False)
        return ("MISSING", path, "file missing or empty", False)

    if not expected_sha:
        detail = "present; missing sha256, not verified"
        if source.get("page_url"):
            detail += f"; page={source['page_url']}"
        return ("PRESENT_UNVERIFIED", path, detail, False)

    ok, detail = file_matches(path, expected_sha, expected_size)
    if ok:
        return ("OK", path, detail, True)
    return ("BAD", path, detail, False)


def list_bundles() -> int:
    data = load_catalog()
    for name, bundle in sorted((data.get("bundles") or {}).items()):
        print(f"{name}\t{bundle.get('title', '')}\t{bundle.get('tutorial', '')}")
    return 0


def check_catalog() -> int:
    data = load_catalog()
    bundles = data.get("bundles") or {}
    model_count = sum(len(bundle.get("models") or []) for bundle in bundles.values())
    print(f"OK\tcatalog\t{CATALOG_FILE}")
    print(f"version\t{data['version']}")
    print(f"bundles\t{len(bundles)}")
    print(f"models\t{model_count}")
    return 0


def unique_values(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        if value and value not in seen:
            seen.add(value)
            out.append(value)
    return out


def status_record_key(model: dict[str, Any]) -> str:
    return f"{model['directory']}/{model['filename']}"


def expected_sha(model: dict[str, Any]) -> str:
    return str(download_info(model).get("sha256") or "").lower()


def expected_size(model: dict[str, Any]) -> str:
    value = download_info(model).get("size_bytes")
    return "" if value is None else str(value)


def best_status_model(models: list[dict[str, Any]]) -> dict[str, Any]:
    for model in models:
        if expected_sha(model):
            return model
    return models[0]


def status_conflict(models: list[dict[str, Any]]) -> str:
    modes = unique_values([download_mode(model) for model in models])
    methods = unique_values([download_method(model) for model in models if download_method(model)])
    hashes = unique_values([expected_sha(model) for model in models if expected_sha(model)])
    sizes = unique_values([expected_size(model) for model in models if expected_size(model)])
    details: list[str] = []
    if len(modes) > 1:
        details.append(f"download.mode differs: {', '.join(modes)}")
    if len(methods) > 1:
        details.append(f"download.method differs: {', '.join(methods)}")
    if len(hashes) > 1:
        details.append(f"sha256 differs: {', '.join(hashes)}")
    if len(sizes) > 1:
        details.append(f"size_bytes differs: {', '.join(sizes)}")
    return "; ".join(details)


def print_status_record(state: str, record: dict[str, Any]) -> None:
    print(f"  - {', '.join(record['ids'])}")
    print(f"    target: {record['target']}")
    print(f"    path: {record['path']}")
    print(f"    bundles: {', '.join(record['bundles'])}")
    if record.get("source"):
        print(f"    source: {record['source']}")
    if record.get("action"):
        print(f"    action: {record['action']}")
    print(f"    detail: {record['detail']}")


def status_action(state: str, model: dict[str, Any], bundle_names: list[str]) -> str:
    download = download_info(model)
    mode = str(download["mode"])
    if state == "MISSING" and mode == "auto":
        return f"./scripts/models.sh download {bundle_names[0]}"
    if state == "MANUAL":
        source = source_info(model)
        page = source.get("page_url")
        if page:
            return f"打开 source page 下载后放到 target: {page}"
        return "确认可信来源后手动下载到 target"
    if state == "BLOCKED":
        return "补齐 catalog 的可信来源和 sha256, 或改成 manual"
    if state == "BAD":
        return "检查文件是否下载错版本; 脚本不会自动覆盖已有文件"
    if state == "PRESENT_UNVERIFIED":
        return "如需 verify 通过, 为 catalog 补齐 sha256"
    return ""


def collect_status_records(
    data: dict[str, Any],
    bundle_name: str,
    model_root: Path,
    strict: bool,
) -> list[dict[str, Any]]:
    grouped: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    for name, bundle in bundle_items(data, bundle_name):
        for model in bundle.get("models") or []:
            grouped.setdefault(status_record_key(model), []).append((name, model))

    records: list[dict[str, Any]] = []
    for target in sorted(grouped):
        entries = grouped[target]
        models = [model for _, model in entries]
        bundle_names = unique_values([name for name, _ in entries])
        ids = unique_values([str(model["id"]) for model in models])
        conflict = status_conflict(models)
        model = best_status_model(models)
        path = model_path(model_root, model)
        if conflict:
            state, detail, ok = "CONFLICT", conflict, False
        else:
            state, _, detail, ok = model_state(model_root, model, strict=strict)
        records.append(
            {
                "state": state,
                "target": target,
                "path": str(path),
                "ids": ids,
                "bundles": bundle_names,
                "detail": detail,
                "ok": ok,
                "source": source_summary(model),
                "action": status_action(state, model, bundle_names),
            }
        )
    return records


def print_status(mode: str, bundle_name: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    strict = mode == "verify"
    records = collect_status_records(data, bundle_name, model_root, strict)
    scope = bundle_name if bundle_name else "all bundles"
    counters = {
        "ok": 0,
        "present_unverified": 0,
        "missing": 0,
        "manual": 0,
        "blocked": 0,
        "bad": 0,
        "conflict": 0,
    }
    for record in records:
        key = str(record["state"]).lower()
        if key == "present_unverified":
            counters["present_unverified"] += 1
        elif key in counters:
            counters[key] += 1

    print(f"root: {model_root}")
    print(f"scope: {scope}")
    print(f"catalog: {CATALOG_FILE}")
    print("Summary:")
    for key in ("ok", "present_unverified", "missing", "manual", "blocked", "bad", "conflict"):
        print(f"  {key}: {counters[key]}")
    print(f"  total_unique: {len(records)}")

    sections = [
        ("MISSING", "Missing"),
        ("MANUAL", "Manual"),
        ("BLOCKED", "Blocked"),
        ("BAD", "Bad"),
        ("CONFLICT", "Conflict"),
        ("PRESENT_UNVERIFIED", "Present Unverified"),
        ("OK", "OK"),
    ]
    for state, title in sections:
        subset = [record for record in records if record["state"] == state]
        if not subset:
            continue
        print(f"\n{title}:")
        for record in subset:
            print_status_record(state, record)

    failed = sum(1 for record in records if not record["ok"])
    return 1 if failed else 0


def source_summary(model: dict[str, Any]) -> str:
    source = source_info(model)
    platform = source["platform"]
    parts = [str(platform)]
    if source.get("creator"):
        parts.append(f"creator={source['creator']}")
    if source.get("model_id"):
        parts.append(f"model_id={source['model_id']}")
    if source.get("version_id"):
        parts.append(f"version_id={source['version_id']}")
    if source.get("page_url"):
        parts.append(f"page={source['page_url']}")
    return " ".join(parts)


def print_model_plan(model_root: Path, model: dict[str, Any]) -> tuple[int, int, int]:
    path = model_path(model_root, model)
    download = download_info(model)
    mode = str(download["mode"])
    method = str(download.get("method", ""))
    print(f"target: {model['id']} -> {path}")
    print(f"source: {source_summary(model)}")

    if mode == "auto":
        if method == "huggingface":
            size_info = (
                f" size_bytes={download.get('size_bytes')}" if download.get("size_bytes") is not None else ""
            )
            print(
                f"auto: method=huggingface repo={download['repo']} path={download['path']} "
                f"repo_type={download['repo_type']} sha256={download['sha256']}{size_info}"
            )
        elif method == "civitai":
            size_info = (
                f" size_bytes={download.get('size_bytes')}" if download.get("size_bytes") is not None else ""
            )
            print(f"auto: method=civitai url={download['url']} sha256={download['sha256']}{size_info}")
        return (1, 0, 0)

    if mode == "manual":
        print(f"manual: {download['reason']}")
        if source_info(model).get("page_url"):
            print(f"action: 打开 source page 下载, 放到 target 路径")
        else:
            print("action: 先确认可信来源和精确文件, 再放到 target 路径")
        return (0, 1, 0)

    print(f"blocked: {download['reason']}")
    print("action: 补齐 catalog 的可信来源、sha256 或改为 manual")
    return (0, 0, 1)


def print_plan(bundle_name: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    for name, bundle in bundle_items(data, bundle_name):
        auto_count = manual_count = blocked_count = 0
        print(f"## {name} - {bundle.get('title', '')}")
        if bundle.get("blueprint"):
            print(f"blueprint: {bundle['blueprint']}")
        if bundle.get("tutorial"):
            print(f"tutorial: {bundle['tutorial']}")
        for model in bundle.get("models") or []:
            auto_delta, manual_delta, blocked_delta = print_model_plan(model_root, model)
            auto_count += auto_delta
            manual_count += manual_delta
            blocked_count += blocked_delta
        print("Summary:")
        print(f"  auto: {auto_count}")
        print(f"  manual: {manual_count}")
        print(f"  blocked: {blocked_count}")
    return 0


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


def resolve_hf_command() -> list[str]:
    if HF_CLI != "hf":
        resolved_override = shutil.which(HF_CLI) if not os.path.isabs(HF_CLI) else HF_CLI
        if resolved_override and Path(resolved_override).is_file() and os.access(resolved_override, os.X_OK):
            return [resolved_override]
        die(f"HF_CLI is not executable: {HF_CLI}", 2)
    project_hf = ROOT_DIR / ".venv/bin/hf"
    if project_hf.is_file() and os.access(project_hf, os.X_OK):
        return [str(project_hf)]
    resolved_hf = shutil.which(HF_CLI)
    if resolved_hf:
        return [resolved_hf]
    die("hf CLI not found; install huggingface_hub in .venv or set HF_CLI", 2)
    return []


def hf_environment(config_file: Path) -> dict[str, str]:
    env = os.environ.copy()
    hf_endpoint = config_value("HF_ENDPOINT", config_file)
    if hf_endpoint and not env.get("HF_ENDPOINT"):
        env["HF_ENDPOINT"] = hf_endpoint
    return env


def ensure_auto_file_ok(final_path: Path, expected_sha: str, expected_size: Any) -> tuple[bool, str]:
    if not final_path.is_file():
        return False, "missing"
    if final_path.stat().st_size <= 0:
        return False, "empty"
    return file_matches(final_path, expected_sha, expected_size)


def download_huggingface(
    model: dict[str, Any],
    tmp_dir: Path,
    hf_cmd: list[str],
    hf_env: dict[str, str],
) -> Path:
    download = download_info(model)
    remote_path = str(download["path"])
    args = hf_cmd + ["download", str(download["repo"]), remote_path, "--local-dir", str(tmp_dir)]
    if str(download["repo_type"]) != "model":
        args += ["--repo-type", str(download["repo_type"])]
    result = subprocess.run(args, check=False, env=hf_env)
    if result.returncode != 0:
        die(f"hf download failed", 4)

    remote_basename = Path(remote_path).name
    candidates = [
        tmp_dir / remote_basename,
        tmp_dir / remote_path,
    ]
    downloaded_path = next((candidate for candidate in candidates if candidate.is_file()), None)
    if downloaded_path is None:
        downloaded_path = next(tmp_dir.rglob(remote_basename), None)
    if downloaded_path is None or not downloaded_path.is_file():
        die(f"downloaded file not found after hf download: {remote_path}", 4)
    return downloaded_path


def download_url(model: dict[str, Any], tmp_dir: Path) -> Path:
    download = download_info(model)
    target = tmp_dir / model["filename"]
    request = urllib.request.Request(
        str(download["url"]),
        headers={"User-Agent": "comfy-shell-models/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response, target.open("wb") as output:
            shutil.copyfileobj(response, output, 1024 * 1024)
    except OSError as exc:
        die(f"url download failed: {exc}", 4)
    return target


def print_download_next(manual: int, blocked: int, failed: int) -> None:
    print("Next:")
    if manual:
        print("  1. 按 manual 列表打开 source page 下载")
        print("  2. 放到 target 路径")
        print("  3. 重新执行 status 或 verify")
    if blocked:
        print("  - blocked 条目需要先补 catalog: 可信来源、sha256, 或改成 manual")
    if failed:
        print("  - failed 条目看上方错误原因, 修复网络、hash 或目标文件后重试")
    if not manual and not blocked and not failed:
        print("  - auto 条目已处理完成; 可执行 verify 做严格校验")


def download_bundle(bundle_name: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    hf_env = hf_environment(config_file)

    section("Download Plan")
    print_plan(bundle_name, config_file)
    section("Download")

    hf_cmd: list[str] | None = None
    stats = {
        "success": 0,
        "skipped_existing": 0,
        "manual": 0,
        "blocked": 0,
        "failed": 0,
    }

    bundle = (data.get("bundles") or {}).get(bundle_name)
    if bundle is None:
        die(f"unknown bundle: {bundle_name}", 2)

    for model in bundle.get("models") or []:
        model_id = model["id"]
        final_path = model_path(model_root, model)
        download = download_info(model)
        mode = str(download["mode"])
        method = str(download.get("method", ""))

        if mode == "manual":
            stats["manual"] += 1
            source = source_info(model)
            detail = f"{final_path}; {download['reason']}"
            if source.get("page_url"):
                detail += f"; page={source['page_url']}"
            event("MANUAL", model_id, detail)
            continue

        if mode == "blocked":
            stats["blocked"] += 1
            event("BLOCKED", model_id, f"{final_path}; {download['reason']}")
            continue

        expected_sha = str(download["sha256"]).lower()
        expected_size = download.get("size_bytes")
        final_path.parent.mkdir(parents=True, exist_ok=True)

        if final_path.exists():
            ok, detail = ensure_auto_file_ok(final_path, expected_sha, expected_size)
            if ok:
                stats["skipped_existing"] += 1
                event("SKIPPED", model_id, str(final_path))
                continue
            stats["failed"] += 1
            event("FAILED", model_id, f"existing target mismatch, refused overwrite: {detail}; {final_path}")
            continue

        event("DOWNLOAD", model_id, f"method={method} target={final_path}")
        tmp_dir = Path(tempfile.mkdtemp(prefix="comfy-shell-model."))
        try:
            try:
                if method == "huggingface":
                    if hf_cmd is None:
                        hf_cmd = resolve_hf_command()
                    downloaded_path = download_huggingface(model, tmp_dir, hf_cmd, hf_env)
                elif method == "civitai":
                    downloaded_path = download_url(model, tmp_dir)
                else:
                    die(f"unsupported download method: {method}", 2)

                ok, detail = file_matches(downloaded_path, expected_sha, expected_size)
                if not ok:
                    stats["failed"] += 1
                    event("FAILED", model_id, detail)
                    continue
                shutil.move(str(downloaded_path), str(final_path))
                stats["success"] += 1
                event("SUCCESS", model_id, str(final_path))
            except CliError as exc:
                if exc.code == 2:
                    raise
                stats["failed"] += 1
                event("FAILED", model_id, str(exc))
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    section("Summary")
    print(f"success: {stats['success']}")
    print(f"skipped_existing: {stats['skipped_existing']}")
    print(f"manual: {stats['manual']}")
    print(f"blocked: {stats['blocked']}")
    print(f"failed: {stats['failed']}")
    print_download_next(stats["manual"], stats["blocked"], stats["failed"])

    section("Status")
    print_status("status", bundle_name, config_file)
    return 4 if stats["failed"] else 0


def main(argv: list[str]) -> int:
    if not argv:
        return 2

    command = argv[0]
    args = argv[1:]

    if command == "list":
        if args:
            die("list takes no arguments", 2)
        section("Model Bundles")
        return list_bundles()

    if command == "check":
        if args:
            die("check takes no arguments", 2)
        section("Model Catalog Check")
        return check_catalog()

    if command == "inspect":
        if len(args) != 1:
            die("inspect requires one workflow file", 2)
        section("Workflow Models")
        return inspect_workflow(args[0])

    if command in {"status", "verify"}:
        parsed_args, config_file = parse_profile_args(command, args)
        if len(parsed_args) > 1:
            die(f"{command} takes zero or one bundle", 2)
        section("Model Status" if command == "status" else "Model Verify")
        return print_status(command, parsed_args[0] if parsed_args else "", config_file)

    if command == "plan":
        parsed_args, config_file = parse_profile_args(command, args)
        if len(parsed_args) != 1:
            die("plan requires one bundle", 2)
        section("Model Plan")
        return print_plan(parsed_args[0], config_file)

    if command == "download":
        parsed_args, config_file = parse_profile_args(command, args)
        if len(parsed_args) != 1:
            die("download requires one bundle", 2)
        return download_bundle(parsed_args[0], config_file)

    die(f"unknown command: {command}", 2)
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except CliError as exc:
        sys.stdout.flush()
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(exc.code)
