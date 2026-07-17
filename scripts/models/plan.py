from __future__ import annotations

from pathlib import Path
from typing import Any

from scripts.models.catalog import (
    bundle_items,
    download_info,
    expected_size,
    load_catalog,
    model_path,
    selected_model_entry,
    source_info,
    source_summary,
    status_record_key,
)
from scripts.models.common import model_root_from_config


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


def print_model_info(model_id: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    bundle_names, model = selected_model_entry(data, model_id)
    download = download_info(model)
    mode = str(download["mode"])
    fields = {
        "id": str(model["id"]),
        "bundles": ",".join(bundle_names),
        "target": status_record_key(model),
        "path": str(model_path(model_root, model)),
        "directory": str(model["directory"]),
        "filename": str(model["filename"]),
        "mode": mode,
        "method": str(download.get("method", "")) if mode == "auto" else "",
        "sha256": str(download.get("sha256") or ""),
        "size_bytes": expected_size(model),
        "source": source_summary(model),
    }
    for key, value in fields.items():
        print(f"{key}\t{value}")
    return 0


def print_plan(bundle_name: str, model_id: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    if model_id:
        bundle_names, model = selected_model_entry(data, model_id)
        print(f"## model {model_id}")
        print(f"bundles: {', '.join(bundle_names)}")
        auto_count, manual_count, blocked_count = print_model_plan(model_root, model)
        print("Summary:")
        print(f"  auto: {auto_count}")
        print(f"  manual: {manual_count}")
        print(f"  blocked: {blocked_count}")
        return 0

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
