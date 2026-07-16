#!/usr/bin/env python3
"""models.sh implementation.

This module is intentionally invoked through scripts/models.sh. It uses the
single repository .venv managed by scripts/local.sh bootstrap.
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
import zlib
from pathlib import Path
from typing import Any


ROOT_DIR = Path(os.environ.get("ROOT_DIR", Path(__file__).resolve().parents[2]))
DEFAULT_CONFIG_FILE = ROOT_DIR / ".env"
CATALOG_FILE = Path(os.environ.get("CATALOG_FILE", ROOT_DIR / "configs/models/catalog.yaml"))
HF_CLI = os.environ.get("HF_CLI", "hf")


class CliError(Exception):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


def die(message: str, code: int = 1) -> None:
    raise CliError(message, code)


def section(name: str) -> None:
    print(f"\n===== {name} =====")


def event(kind: str, name: str, detail: str = "") -> None:
    print(f"{kind:<10} {name:<18} {detail}")


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


def load_catalog() -> dict[str, Any]:
    require_catalog()
    yaml = load_yaml_module()
    with CATALOG_FILE.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def bundle_items(data: dict[str, Any], bundle_name: str) -> list[tuple[str, dict[str, Any]]]:
    bundles = data.get("bundles") or {}
    if bundle_name:
        if bundle_name not in bundles:
            die(f"unknown bundle: {bundle_name}", 2)
        return [(bundle_name, bundles[bundle_name])]
    return sorted(bundles.items())


def model_path(model_root: Path, model: dict[str, Any]) -> Path:
    return model_root / model["directory"] / model["filename"]


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def model_state(model_root: Path, model: dict[str, Any], strict: bool = False) -> tuple[str, Path, str, bool]:
    path = model_path(model_root, model)
    source = model.get("source", "huggingface")
    expected_sha = model.get("sha256") or ""
    expected_size = model.get("size_bytes")
    note = model.get("note", "")

    if source == "manual":
        detail = note or "manual download required"
        exists = path.is_file() and path.stat().st_size > 0
        suffix = "present" if exists else "missing"
        return ("MANUAL", path, f"{suffix}; {detail}", False)

    if source == "huggingface" and not expected_sha:
        exists = path.is_file() and path.stat().st_size > 0
        suffix = "present" if exists else "missing"
        return ("BLOCKED", path, f"{suffix}; missing sha256 in catalog", False)

    if not path.is_file() or path.stat().st_size <= 0:
        return ("MISSING", path, "file missing or empty", False)

    if expected_size is not None and path.stat().st_size != int(expected_size):
        return ("BAD", path, f"size mismatch: {path.stat().st_size} != {expected_size}", False)

    if expected_sha:
        actual_sha = file_sha256(path)
        if actual_sha.lower() != expected_sha.lower():
            return ("BAD", path, f"sha256 mismatch: {actual_sha}", False)
        return ("OK", path, f"sha256={actual_sha}", True)

    if strict:
        return ("BLOCKED", path, "missing sha256 in catalog", False)
    return ("OK", path, "present", True)


def list_bundles() -> int:
    data = load_catalog()
    for name, bundle in sorted((data.get("bundles") or {}).items()):
        print(f"{name}\t{bundle.get('title', '')}\t{bundle.get('tutorial', '')}")
    return 0


def print_status(mode: str, bundle_name: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    failed = 0
    strict = mode == "verify"
    for name, bundle in bundle_items(data, bundle_name):
        print(f"## {name} - {bundle.get('title', '')}")
        for model in bundle.get("models") or []:
            state, path, detail, ok = model_state(model_root, model, strict=strict)
            print(f"{state}\t{model['id']}\t{path}\t{detail}")
            if not ok:
                failed += 1
    return 1 if failed else 0


def print_plan(bundle_name: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    for name, bundle in bundle_items(data, bundle_name):
        print(f"## {name} - {bundle.get('title', '')}")
        if bundle.get("blueprint"):
            print(f"blueprint: {bundle['blueprint']}")
        if bundle.get("tutorial"):
            print(f"tutorial: {bundle['tutorial']}")
        for model in bundle.get("models") or []:
            source = model.get("source", "huggingface")
            path = model_path(model_root, model)
            if source == "manual":
                note = model.get("note", "manual download required")
                print(f"TARGET\t{model['id']}\t{path}")
                print(f"MANUAL\t{model['id']}\t{note}")
                continue
            if source != "huggingface":
                print(f"UNSUPPORTED\t{model['id']}\tsource={source}")
                continue
            print(f"TARGET\t{model['id']}\t{path}")
            if not model.get("sha256"):
                print(f"BLOCKED\t{model['id']}\tmissing sha256 in catalog; download disabled")
                continue
            repo_type = model.get("repo_type", "model")
            size_info = f"\tsize_bytes={model.get('size_bytes')}" if model.get("size_bytes") is not None else ""
            print(
                f"HF\t{model['repo']}\t{model['path']}\trepo_type={repo_type}"
                f"\tsha256={model['sha256']}{size_info}\t--local-dir {path.parent}"
            )
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
    project_hf = ROOT_DIR / ".venv/bin/hf"
    if project_hf.is_file() and os.access(project_hf, os.X_OK):
        return [str(project_hf)]
    resolved_hf = shutil.which(HF_CLI)
    if resolved_hf:
        return [resolved_hf]
    die("hf CLI not found; install huggingface_hub in .venv or set HF_CLI", 2)
    return []


def download_rows(data: dict[str, Any], bundle_name: str, model_root: Path) -> list[dict[str, Any]]:
    bundles = data.get("bundles") or {}
    bundle = bundles.get(bundle_name)
    if bundle is None:
        die(f"unknown bundle: {bundle_name}", 2)
    rows: list[dict[str, Any]] = []
    for model in bundle.get("models") or []:
        source = model.get("source", "huggingface")
        row = {
            "source": source,
            "model_id": model["id"],
            "repo": model.get("repo", ""),
            "remote_path": model.get("path", ""),
            "local_dir": model_root / model["directory"],
            "filename": model["filename"],
            "repo_type": model.get("repo_type", "model"),
            "sha256": model.get("sha256", ""),
            "size_bytes": model.get("size_bytes"),
        }
        if source == "manual":
            rows.append(row)
        elif source != "huggingface":
            die(f"unsupported source for {model['id']}: {source}", 2)
        elif not row["sha256"]:
            row["source"] = "blocked"
            rows.append(row)
        else:
            rows.append(row)
    return rows


def download_bundle(bundle_name: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)

    section("Download Plan")
    print_plan(bundle_name, config_file)
    section("Download")

    failed = False
    hf_cmd: list[str] | None = None
    for row in download_rows(data, bundle_name, model_root):
        model_id = row["model_id"]
        local_dir = Path(row["local_dir"])
        filename = row["filename"]

        if row["source"] == "manual":
            event("MANUAL", model_id, str(local_dir / filename))
            continue
        if row["source"] == "blocked":
            event("BLOCKED", model_id, "missing sha256 in catalog")
            failed = True
            continue

        remote_path = row["remote_path"]
        remote_basename = Path(remote_path).name
        if remote_basename != filename:
            die(
                f"catalog filename does not match remote basename for {model_id}: "
                f"{filename} != {remote_basename}",
                2,
            )

        local_dir.mkdir(parents=True, exist_ok=True)
        final_path = local_dir / filename
        expected_sha = row["sha256"]
        if final_path.is_file():
            actual_sha = file_sha256(final_path)
            if actual_sha == expected_sha:
                event("OK", model_id, str(final_path))
                continue
            die(f"existing model hash mismatch, refuse overwrite: {final_path}", 4)

        if hf_cmd is None:
            hf_cmd = resolve_hf_command()

        event("DOWNLOAD", model_id, str(local_dir))
        tmp_dir = Path(tempfile.mkdtemp(prefix="comfy-shell-model."))
        try:
            args = hf_cmd + ["download", row["repo"], remote_path, "--local-dir", str(tmp_dir)]
            if row["repo_type"] != "model":
                args += ["--repo-type", row["repo_type"]]
            result = subprocess.run(args, check=False)
            if result.returncode != 0:
                die(f"hf download failed for {model_id}", 4)

            candidates = [
                tmp_dir / remote_basename,
                tmp_dir / remote_path,
            ]
            downloaded_path = next((candidate for candidate in candidates if candidate.is_file()), None)
            if downloaded_path is None:
                downloaded_path = next(tmp_dir.rglob(remote_basename), None)
            if downloaded_path is None or not downloaded_path.is_file():
                die(f"downloaded file not found after hf download: {remote_path}", 4)

            actual_sha = file_sha256(downloaded_path)
            if actual_sha != expected_sha:
                die(f"downloaded hash mismatch for {model_id}: {actual_sha} != {expected_sha}", 4)

            expected_size = row["size_bytes"]
            if expected_size is not None and downloaded_path.stat().st_size != int(expected_size):
                die(
                    f"downloaded size mismatch for {model_id}: "
                    f"{downloaded_path.stat().st_size} != {expected_size}",
                    4,
                )

            final_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(downloaded_path), str(final_path))
            event("OK", model_id, str(final_path))
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    if failed:
        die("some catalog entries are blocked; add sha256 or mark them manual", 2)

    section("Status")
    return print_status("status", bundle_name, config_file)


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
