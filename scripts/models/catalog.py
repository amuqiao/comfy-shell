from __future__ import annotations

from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlparse

from scripts.models.common import (
    CATALOG_FILE,
    die,
    ensure_path_within,
    load_yaml_module,
    require_catalog,
    require_dict,
    require_str,
)


VALID_DOWNLOAD_MODES = {"auto", "manual", "blocked"}
VALID_AUTO_METHODS = {"huggingface", "civitai"}
VALID_URL_SCHEMES = {"http", "https", "file"}
AUTO_ONLY_DOWNLOAD_KEYS = {"method", "repo_type", "repo", "path", "url", "sha256", "size_bytes"}


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


def validate_model_directory(value: str, label: str) -> None:
    if value.startswith("/") or "\\" in value or "\x00" in value:
        die(f"invalid catalog: {label}.directory must be a relative model directory", 2)
    parts = value.split("/")
    if not parts or any(part in {"", ".", ".."} for part in parts):
        die(f"invalid catalog: {label}.directory must not contain empty, '.', or '..' path segments", 2)


def validate_model_filename(value: str, label: str) -> None:
    if value in {".", ".."} or "/" in value or "\\" in value or "\x00" in value:
        die(f"invalid catalog: {label}.filename must be a single filename", 2)
    if PurePosixPath(value).name != value:
        die(f"invalid catalog: {label}.filename must not contain path separators", 2)


def model_label(bundle_name: str, model: dict[str, Any], index: int) -> str:
    return f"bundles.{bundle_name}.models[{index}]({model.get('id', '<missing-id>')})"


def validate_model(bundle_name: str, model: dict[str, Any], index: int) -> None:
    label = model_label(bundle_name, model, index)
    require_model_str(model, "id", label)
    validate_model_directory(require_model_str(model, "directory", label), label)
    validate_model_filename(require_model_str(model, "filename", label), label)
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
        extra_keys = sorted(key for key in AUTO_ONLY_DOWNLOAD_KEYS if key in download)
        if extra_keys:
            die(
                f"invalid catalog: {label}.download uses auto-only keys with mode={mode}: "
                f"{', '.join(extra_keys)}",
                2,
            )
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


def catalog_model_entries(
    data: dict[str, Any],
    bundle_name: str = "",
    model_id: str = "",
) -> list[tuple[str, dict[str, Any]]]:
    entries: list[tuple[str, dict[str, Any]]] = []
    for name, bundle in bundle_items(data, bundle_name):
        for model in bundle.get("models") or []:
            if model_id and model.get("id") != model_id:
                continue
            entries.append((name, model))
    if model_id and not entries:
        scope = f" in bundle {bundle_name}" if bundle_name else ""
        die(f"unknown model id{scope}: {model_id}", 2)
    return entries


def source_info(model: dict[str, Any]) -> dict[str, Any]:
    return require_dict(model.get("source"), f"{model['id']}.source")


def download_info(model: dict[str, Any]) -> dict[str, Any]:
    return require_dict(model.get("download"), f"{model['id']}.download")


def download_mode(model: dict[str, Any]) -> str:
    return str(download_info(model)["mode"])


def download_method(model: dict[str, Any]) -> str:
    return str(download_info(model).get("method", ""))


def model_path(model_root: Path, model: dict[str, Any]) -> Path:
    path = model_root / model["directory"] / model["filename"]
    ensure_path_within(model_root, path, f"model target for {model['id']}")
    return path


def unique_values(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        if value and value not in seen:
            seen.add(value)
            out.append(value)
    return out


def unique_field_values(models: list[dict[str, Any]], label: str) -> list[str]:
    scope, key = label.split(".", 1)
    values: list[str] = []
    for model in models:
        mapping = source_info(model) if scope == "source" else download_info(model)
        value = mapping.get(key)
        values.append("" if value is None else str(value))
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        if value not in seen:
            seen.add(value)
            out.append(value if value else "<empty>")
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
    compare_fields = [
        "download.mode",
        "download.method",
        "download.repo_type",
        "download.repo",
        "download.path",
        "download.url",
        "download.sha256",
        "download.size_bytes",
        "source.platform",
        "source.page_url",
        "source.creator",
        "source.model_id",
        "source.version_id",
        "source.repo",
    ]
    details: list[str] = []
    for label in compare_fields:
        values = unique_field_values(models, label)
        if len(values) > 1:
            details.append(f"{label} differs: {', '.join(values)}")
    return "; ".join(details)


def selected_model_entry(data: dict[str, Any], model_id: str) -> tuple[list[str], dict[str, Any]]:
    entries = catalog_model_entries(data, model_id=model_id)
    models = [model for _, model in entries]
    conflict = status_conflict(models)
    targets = unique_values([status_record_key(model) for model in models])
    if len(targets) > 1:
        conflict = f"{conflict}; " if conflict else ""
        conflict += f"target differs: {', '.join(targets)}"
    if conflict:
        die(f"model id {model_id} has conflicting catalog declarations: {conflict}", 2)
    model = best_status_model(models)
    target = status_record_key(model)
    target_entries = [(name, entry) for name, entry in catalog_model_entries(data) if status_record_key(entry) == target]
    target_conflict = status_conflict([entry for _, entry in target_entries])
    if target_conflict:
        ids = ", ".join(unique_values([str(entry["id"]) for _, entry in target_entries]))
        die(
            f"model target {target} has conflicting catalog declarations for ids {ids}: {target_conflict}",
            2,
        )
    return (unique_values([name for name, _ in entries]), model)


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


def list_bundles() -> int:
    data = load_catalog()
    for name, bundle in sorted((data.get("bundles") or {}).items()):
        print(f"{name}\t{bundle.get('title', '')}\t{bundle.get('tutorial', '')}")
    return 0


def list_models(bundle_name: str) -> int:
    data = load_catalog()
    print("BUNDLE\tMODEL_ID\tTARGET\tMODE\tMETHOD\tSOURCE")
    for name, model in catalog_model_entries(data, bundle_name=bundle_name):
        download = download_info(model)
        mode = str(download["mode"])
        method = str(download.get("method", "")) if mode == "auto" else ""
        print(
            "\t".join(
                [
                    name,
                    str(model["id"]),
                    status_record_key(model),
                    mode,
                    method,
                    source_summary(model),
                ]
            )
        )
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
