#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from io import StringIO
from typing import Any, Optional, Union


GPU_FIELDS = [
    "index",
    "uuid",
    "name",
    "temperature_c",
    "gpu_utilization_percent",
    "memory_used_mib",
    "memory_total_mib",
    "power_draw_w",
    "power_limit_w",
    "compute_mode",
    "driver_version",
]

PROCESS_FIELDS = [
    "gpu_uuid",
    "pid",
    "process_name",
    "used_memory_mib",
]

GPU_SECTION_MARKER = "__REMOTE_GPU_SUMMARY__"
PROCESS_SECTION_MARKER = "__REMOTE_GPU_PROCESSES__"
HIGH_MEMORY_UTILIZATION_PERCENT = 80


def _parse_number(value: str) -> Optional[Union[int, float]]:
    value = value.strip()
    if value in {"", "N/A", "[Not Supported]"}:
        return None

    try:
        number = float(value)
    except ValueError:
        return None

    if number.is_integer():
        return int(number)
    return number


def _parse_csv_rows(text: str) -> list[list[str]]:
    if not text.strip():
        return []
    reader = csv.reader(StringIO(text), skipinitialspace=True)
    return [[cell.strip() for cell in row] for row in reader if row]


def _build_gpu(row: list[str]) -> dict[str, Any]:
    if len(row) != len(GPU_FIELDS):
        raise ValueError(f"invalid GPU row field count: expected {len(GPU_FIELDS)} got {len(row)}")

    result: dict[str, Any] = {}
    for key, value in zip(GPU_FIELDS, row):
        if key in {"uuid", "name", "compute_mode", "driver_version"}:
            result[key] = value
        else:
            result[key] = _parse_number(value)

    used = result["memory_used_mib"]
    total = result["memory_total_mib"]
    if isinstance(used, (int, float)) and isinstance(total, (int, float)) and total > 0:
        result["memory_utilization_percent"] = round((used / total) * 100, 1)
    else:
        result["memory_utilization_percent"] = None
    return result


def _build_process(row: list[str], gpu_index_by_uuid: dict[str, Any]) -> dict[str, Any]:
    if len(row) != len(PROCESS_FIELDS):
        raise ValueError(f"invalid process row field count: expected {len(PROCESS_FIELDS)} got {len(row)}")

    result: dict[str, Any] = {}
    for key, value in zip(PROCESS_FIELDS, row):
        if key in {"gpu_uuid", "process_name"}:
            result[key] = value
        else:
            result[key] = _parse_number(value)

    result["gpu_index"] = gpu_index_by_uuid.get(str(result["gpu_uuid"]))
    return result


def parse_snapshot(text: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    sections: dict[str, list[str]] = {"gpu": [], "processes": []}
    current: Optional[str] = None

    for line in text.splitlines():
        if line == GPU_SECTION_MARKER:
            current = "gpu"
            continue
        if line == PROCESS_SECTION_MARKER:
            current = "processes"
            continue
        if current is None:
            if line.strip():
                raise ValueError(f"unexpected snapshot line before section marker: {line}")
            continue
        sections[current].append(line)

    gpus = [_build_gpu(row) for row in _parse_csv_rows("\n".join(sections["gpu"]))]
    gpu_index_by_uuid = {str(gpu["uuid"]): gpu["index"] for gpu in gpus}
    processes = [
        _build_process(row, gpu_index_by_uuid)
        for row in _parse_csv_rows("\n".join(sections["processes"]))
    ]
    return gpus, processes


def _display(value: Any) -> str:
    if value is None:
        return "N/A"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def _percent(value: Any) -> str:
    if value is None:
        return "N/A"
    return f"{_display(value)}%"


def _temperature(value: Any) -> str:
    if value is None:
        return "N/A"
    return f"{value} C"


def _power(draw: Any, limit: Any) -> str:
    return f"{_display(draw)} W / {_display(limit)} W"


def _memory(value_mib: Any) -> str:
    if not isinstance(value_mib, (int, float)):
        return "N/A"
    if value_mib >= 1024:
        return f"{value_mib / 1024:.1f} GiB"
    return f"{value_mib:g} MiB"


def _memory_pair(used_mib: Any, total_mib: Any, util_percent: Any) -> str:
    marker = ""
    if isinstance(util_percent, (int, float)) and util_percent >= HIGH_MEMORY_UTILIZATION_PERCENT:
        marker = " 高"
    return f"{_memory(used_mib)} / {_memory(total_mib)} ({_percent(util_percent)}){marker}"


def _compute_mode(value: Any) -> str:
    mode = _display(value)
    descriptions = {
        "Exclusive_Process": "独占进程",
        "Exclusive_Thread": "独占线程",
        "Prohibited": "禁止计算",
    }
    if mode in descriptions:
        return f"{mode} ({descriptions[mode]})"
    return mode


def _process_label(path: str) -> str:
    if not path:
        return "unknown"
    return os.path.basename(path) or path


def _gpu_processes(gpu: dict[str, Any], processes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [process for process in processes if process.get("gpu_index") == gpu.get("index")]


def _common_gpu_name(gpus: list[dict[str, Any]]) -> str:
    names = {str(gpu.get("name")) for gpu in gpus if gpu.get("name")}
    if len(names) == 1:
        return names.pop()
    return "GPU"


def _total_memory(gpus: list[dict[str, Any]]) -> tuple[float, float, Optional[float]]:
    used = sum(
        float(gpu["memory_used_mib"])
        for gpu in gpus
        if isinstance(gpu.get("memory_used_mib"), (int, float))
    )
    total = sum(
        float(gpu["memory_total_mib"])
        for gpu in gpus
        if isinstance(gpu.get("memory_total_mib"), (int, float))
    )
    if total > 0:
        return used, total, round((used / total) * 100, 1)
    return used, total, None


def print_human(host: str, gpus: list[dict[str, Any]], processes: list[dict[str, Any]]) -> None:
    print(f"远程主机: {host}")

    if not gpus:
        print("\nGPU 状态: 未返回 GPU 信息。")
        return

    total_used, total_capacity, total_util = _total_memory(gpus)
    max_gpu_util = max(
        [
            float(gpu["gpu_utilization_percent"])
            for gpu in gpus
            if isinstance(gpu.get("gpu_utilization_percent"), (int, float))
        ],
        default=0,
    )
    print(
        "\nGPU 状态: "
        f"{len(gpus)} 张 {_common_gpu_name(gpus)}, "
        f"当前最高计算利用率 {_percent(round(max_gpu_util, 1))}, "
        f"显存占用 {_memory(total_used)} / {_memory(total_capacity)} ({_percent(total_util)}), "
        f"GPU 进程 {len(processes)} 个。"
    )

    for gpu in gpus:
        print(f"\nGPU {gpu['index']}  {_display(gpu['name'])}")
        print(f"  温度: {_temperature(gpu['temperature_c'])}")
        print(f"  利用率: {_percent(gpu['gpu_utilization_percent'])}")
        print(
            "  显存: "
            f"{_memory_pair(gpu['memory_used_mib'], gpu['memory_total_mib'], gpu['memory_utilization_percent'])}"
        )
        print(f"  功耗: {_power(gpu['power_draw_w'], gpu['power_limit_w'])}")
        print(f"  模式: {_compute_mode(gpu['compute_mode'])}")
        print(f"  驱动: {_display(gpu['driver_version'])}")

        gpu_processes = _gpu_processes(gpu, processes)
        if not gpu_processes:
            print("  进程: 无")
            continue

        print("  进程:")
        for process in gpu_processes:
            full_path = str(process["process_name"])
            print(
                "    "
                f"{_display(process['pid'])}  "
                f"{_process_label(full_path)}  "
                f"{_memory(process['used_memory_mib'])}  "
                f"{full_path}"
            )

    unknown_processes = [process for process in processes if process.get("gpu_index") is None]
    if unknown_processes:
        print("\n未关联到 GPU 的进程:")
        for process in unknown_processes:
            print(
                "  "
                f"{_display(process['pid'])}  "
                f"{_process_label(str(process['process_name']))}  "
                f"{_memory(process['used_memory_mib'])}  "
                f"{process['process_name']}"
            )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="format a remote nvidia-smi snapshot")
    parser.add_argument("--host", required=True)
    parser.add_argument("--json", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        gpus, processes = parse_snapshot(sys.stdin.read())
    except ValueError as exc:
        print(f"ERROR: invalid nvidia-smi snapshot: {exc}", file=sys.stderr)
        return 4

    if args.json:
        payload = {
            "host": args.host,
            "gpus": gpus,
            "processes": processes,
        }
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        print_human(args.host, gpus, processes)

    return 0 if gpus else 1


if __name__ == "__main__":
    raise SystemExit(main())
