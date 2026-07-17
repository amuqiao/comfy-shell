from __future__ import annotations

from pathlib import Path
from typing import Any

from scripts.models.common import die, model_root_from_config


ROOT_LABEL = "(root)"
SUPPORT_GROUPS = {"configs"}


def format_bytes(value: float) -> str:
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    size = float(value)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} TiB"


def inventory_group_key(relative_path: Path) -> str:
    parts = relative_path.parts
    if len(parts) <= 1:
        return ROOT_LABEL
    return parts[0]


def inventory_display_name(relative_path: Path, group: str) -> str:
    if group == ROOT_LABEL:
        return relative_path.name
    return relative_path.relative_to(group).as_posix()


def hidden_reason(relative_path: Path, size: int) -> str:
    name = relative_path.name
    group = inventory_group_key(relative_path)
    if size == 0 and name.startswith("put_") and name.endswith("_here"):
        return "placeholder"
    if group in SUPPORT_GROUPS and relative_path.suffix.lower() in {".yaml", ".yml"}:
        return "support"
    return ""


def collect_inventory(model_root: Path, show_all: bool = False) -> tuple[list[dict[str, Any]], dict[str, int]]:
    grouped: dict[str, dict[str, Any]] = {}
    hidden = {"placeholder": 0, "support": 0}
    for path in sorted(model_root.rglob("*")):
        if not path.is_file():
            continue
        relative_path = path.relative_to(model_root)
        size = path.stat().st_size
        reason = hidden_reason(relative_path, size)
        if reason and not show_all:
            hidden[reason] += 1
            continue
        group = inventory_group_key(relative_path)
        record = grouped.setdefault(group, {"group": group, "files": [], "bytes": 0})
        display_name = inventory_display_name(relative_path, group)
        if show_all and reason:
            label = "占位" if reason == "placeholder" else "支持配置"
            display_name = f"{display_name} [{label}]"
        record["files"].append(display_name)
        record["bytes"] += size
    return ([grouped[key] for key in sorted(grouped)], hidden)


def print_inventory(config_file: Path, show_all: bool = False) -> int:
    model_root = model_root_from_config(config_file)
    if not model_root.exists():
        die(f"COMFY_MODEL_ROOT does not exist: {model_root}", 2)
    if not model_root.is_dir():
        die(f"COMFY_MODEL_ROOT is not a directory: {model_root}", 2)

    groups, hidden = collect_inventory(model_root, show_all=show_all)
    total_files = sum(len(group["files"]) for group in groups)
    total_bytes = sum(int(group["bytes"]) for group in groups)

    print(f"模型根目录: {model_root}")
    print("摘要:")
    print(f"  模型类型: {len(groups)}")
    print(f"  模型文件: {total_files}")
    print(f"  模型大小: {format_bytes(total_bytes)}")
    if not show_all:
        print("  已隐藏:")
        print(f"    占位文件: {hidden['placeholder']}")
        print(f"    支持配置: {hidden['support']}")
        if hidden["placeholder"] or hidden["support"]:
            print("  提示: 使用 --all 查看占位文件和支持配置。")
    print("\n模型清单:")

    if not groups:
        print("  未发现模型文件。")
        return 0

    for group in groups:
        print(f"\n{group['group']}:")
        print(f"  文件数: {len(group['files'])}")
        print(f"  大小: {format_bytes(int(group['bytes']))}")
        print("  文件:")
        for name in group["files"]:
            print(f"    - {name}")
    return 0
