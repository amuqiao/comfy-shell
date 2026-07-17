from __future__ import annotations

import hashlib
import os
import re
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


def parse_model_args(command_name: str, argv: list[str]) -> tuple[list[str], Path, str, str]:
    args: list[str] = []
    config_file = DEFAULT_CONFIG_FILE
    model_id = ""
    upload_file = ""
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
        elif arg == "--model":
            if index + 1 >= len(argv):
                die("--model requires a model id", 2)
            if model_id:
                die(f"{command_name} accepts at most one --model", 2)
            model_id = argv[index + 1]
            index += 2
        elif arg.startswith("--model="):
            if model_id:
                die(f"{command_name} accepts at most one --model", 2)
            model_id = arg.split("=", 1)[1]
            index += 1
        elif arg == "--file":
            if index + 1 >= len(argv):
                die("--file requires a path", 2)
            upload_file = argv[index + 1]
            index += 2
        elif arg.startswith("--file="):
            upload_file = arg.split("=", 1)[1]
            index += 1
        elif arg.startswith("-"):
            die(f"{command_name} unknown option: {arg}", 2)
        else:
            args.append(arg)
            index += 1
    if model_id and args:
        die(f"{command_name} accepts either a bundle argument or --model, not both", 2)
    return args, config_file, model_id, upload_file


def require_config_file(config_file: Path) -> None:
    if not config_file.is_file():
        die(f"config file not found: {config_file}", 2)


def model_root_from_config(config_file: Path) -> Path:
    exported = os.environ.get("COMFY_MODEL_ROOT")
    if exported:
        return repo_path(exported)
    require_config_file(config_file)
    configured = env_value_from("COMFY_MODEL_ROOT", config_file)
    if not configured:
        die(f"missing required config: COMFY_MODEL_ROOT in process environment or {config_file}", 2)
    return repo_path(configured)


def ensure_path_within(root: Path, path: Path, label: str) -> None:
    root_resolved = root.resolve(strict=False)
    path_resolved = path.resolve(strict=False)
    try:
        path_resolved.relative_to(root_resolved)
    except ValueError:
        die(f"{label} escapes COMFY_MODEL_ROOT: {path}", 2)


def require_catalog() -> None:
    if not CATALOG_FILE.is_file():
        die(f"catalog not found: {CATALOG_FILE}", 2)


def load_yaml_module():
    try:
        import yaml  # type: ignore[import-not-found]
    except Exception as exc:  # pragma: no cover - exact import error varies by host
        die(
            f"PyYAML not available in {os.sys.executable}; run ./scripts/local.sh bootstrap first",
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
