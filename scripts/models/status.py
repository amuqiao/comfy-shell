from __future__ import annotations

from pathlib import Path
from typing import Any

from scripts.models.catalog import (
    best_status_model,
    catalog_model_entries,
    download_info,
    load_catalog,
    model_path,
    selected_model_entry,
    source_info,
    source_summary,
    status_conflict,
    status_record_key,
    unique_values,
)
from scripts.models.common import CATALOG_FILE, file_matches, model_root_from_config


def model_state(model_root: Path, model: dict[str, Any], strict: bool = False) -> tuple[str, Path, str, bool]:
    path = model_path(model_root, model)
    source = source_info(model)
    download = download_info(model)
    mode = str(download["mode"])
    expected = str(download.get("sha256") or "")
    size = download.get("size_bytes")
    reason = str(download.get("reason") or "")

    if mode == "blocked":
        suffix = "present" if path.is_file() and path.stat().st_size > 0 else "missing"
        return ("BLOCKED", path, f"{suffix}; {reason}", False)

    if not path.is_file() or path.stat().st_size <= 0:
        if mode == "manual":
            return ("MANUAL", path, f"missing; {reason}", False)
        return ("MISSING", path, "file missing or empty", False)

    if not expected:
        detail = "present; missing sha256, not verified"
        if source.get("page_url"):
            detail += f"; page={source['page_url']}"
        return ("PRESENT_UNVERIFIED", path, detail, False)

    ok, detail = file_matches(path, expected, size)
    if ok:
        return ("OK", path, detail, True)
    return ("BAD", path, detail, False)


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


def status_action(state: str, model: dict[str, Any], bundle_names: list[str], model_selected: bool) -> str:
    download = download_info(model)
    mode = str(download["mode"])
    if state == "MISSING" and mode == "auto":
        if model_selected:
            return f"./scripts/models.sh download --model {model['id']}"
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
    model_id: str,
    model_root: Path,
    strict: bool,
) -> list[dict[str, Any]]:
    grouped: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    for name, model in catalog_model_entries(data, bundle_name=bundle_name, model_id=model_id):
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
                "action": status_action(state, model, bundle_names, bool(model_id)),
            }
        )
    return records


def print_status(mode: str, bundle_name: str, model_id: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    if model_id:
        selected_model_entry(data, model_id)
    strict = mode == "verify"
    records = collect_status_records(data, bundle_name, model_id, model_root, strict)
    if model_id:
        scope = f"model {model_id}"
    else:
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
