from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path
from typing import Any

from scripts.models.catalog import (
    download_info,
    load_catalog,
    model_path,
    selected_model_entry,
    source_info,
)
from scripts.models.common import (
    HF_CLI,
    ROOT_DIR,
    CliError,
    config_value,
    die,
    event,
    file_matches,
    model_root_from_config,
    repo_path,
    section,
)
from scripts.models.plan import print_plan
from scripts.models.status import print_status


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


def ensure_target_parent(final_path: Path, model_id: str) -> None:
    try:
        final_path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        die(
            "unable to create model target directory: "
            f"{final_path.parent}; COMFY_MODEL_ROOT may point to a path that is not writable on this machine. "
            f"If this is a remote model path, use: ./scripts/remote.sh models download --model {model_id} --detach. "
            "Otherwise fix COMFY_MODEL_ROOT in .env or pass --profile FILE. "
            f"OS error: {exc}",
            4,
        )


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
        die("hf download failed", 4)

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


def download_one_model(
    model_root: Path,
    model: dict[str, Any],
    config_file: Path,
    hf_cmd_ref: list[list[str] | None],
) -> str:
    model_id = str(model["id"])
    final_path = model_path(model_root, model)
    download = download_info(model)
    mode = str(download["mode"])
    method = str(download.get("method", ""))

    if mode == "manual":
        source = source_info(model)
        detail = f"{final_path}; {download['reason']}"
        if source.get("page_url"):
            detail += f"; page={source['page_url']}"
        event("MANUAL", model_id, detail)
        return "manual"

    if mode == "blocked":
        event("BLOCKED", model_id, f"{final_path}; {download['reason']}")
        return "blocked"

    expected_sha = str(download["sha256"]).lower()
    expected_size = download.get("size_bytes")
    ensure_target_parent(final_path, model_id)

    if final_path.exists():
        ok, detail = ensure_auto_file_ok(final_path, expected_sha, expected_size)
        if ok:
            event("SKIPPED", model_id, str(final_path))
            return "skipped_existing"
        event("FAILED", model_id, f"existing target mismatch, refused overwrite: {detail}; {final_path}")
        return "failed"

    event("DOWNLOAD", model_id, f"method={method} target={final_path}")
    tmp_dir = Path(tempfile.mkdtemp(prefix="comfy-shell-model."))
    try:
        try:
            if method == "huggingface":
                if hf_cmd_ref[0] is None:
                    hf_cmd_ref[0] = resolve_hf_command()
                downloaded_path = download_huggingface(model, tmp_dir, hf_cmd_ref[0], hf_environment(config_file))
            elif method == "civitai":
                downloaded_path = download_url(model, tmp_dir)
            else:
                die(f"unsupported download method: {method}", 2)

            ok, detail = file_matches(downloaded_path, expected_sha, expected_size)
            if not ok:
                event("FAILED", model_id, detail)
                return "failed"
            shutil.move(str(downloaded_path), str(final_path))
            event("SUCCESS", model_id, str(final_path))
            return "success"
        except CliError as exc:
            if exc.code == 2:
                raise
            event("FAILED", model_id, str(exc))
            return "failed"
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def download_model(model_id: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    _, model = selected_model_entry(data, model_id)

    section("Download Plan")
    print_plan("", model_id, config_file)
    section("Download")

    stats = {
        "success": 0,
        "skipped_existing": 0,
        "manual": 0,
        "blocked": 0,
        "failed": 0,
    }
    result = download_one_model(model_root, model, config_file, [None])
    stats[result] += 1

    section("Summary")
    print(f"success: {stats['success']}")
    print(f"skipped_existing: {stats['skipped_existing']}")
    print(f"manual: {stats['manual']}")
    print(f"blocked: {stats['blocked']}")
    print(f"failed: {stats['failed']}")
    print_download_next(stats["manual"], stats["blocked"], stats["failed"])

    section("Status")
    print_status("status", "", model_id, config_file)
    if stats["failed"]:
        return 4
    if stats["manual"] or stats["blocked"]:
        return 1
    return 0


def download_bundle(bundle_name: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)

    section("Download Plan")
    print_plan(bundle_name, "", config_file)
    section("Download")

    hf_cmd_ref: list[list[str] | None] = [None]
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
        result = download_one_model(model_root, model, config_file, hf_cmd_ref)
        stats[result] += 1

    section("Summary")
    print(f"success: {stats['success']}")
    print(f"skipped_existing: {stats['skipped_existing']}")
    print(f"manual: {stats['manual']}")
    print(f"blocked: {stats['blocked']}")
    print(f"failed: {stats['failed']}")
    print_download_next(stats["manual"], stats["blocked"], stats["failed"])

    section("Status")
    print_status("status", bundle_name, "", config_file)
    return 4 if stats["failed"] else 0


def install_upload(model_id: str, upload_file: str, config_file: Path) -> int:
    data = load_catalog()
    model_root = model_root_from_config(config_file)
    _, model = selected_model_entry(data, model_id)
    download = download_info(model)
    expected = str(download.get("sha256") or "").lower()
    if not expected:
        die(f"model {model_id} has no sha256; upload install is disabled for reliability", 2)
    expected_size = download.get("size_bytes")
    source = repo_path(upload_file)
    final_path = model_path(model_root, model)

    section("Install Upload")
    event("MODEL", model_id)
    event("SOURCE", str(source))
    event("TARGET", str(final_path))

    if not source.is_file() or source.stat().st_size <= 0:
        die(f"upload file missing or empty: {source}", 4)

    if final_path.exists():
        ok, detail = ensure_auto_file_ok(final_path, expected, expected_size)
        if ok:
            event("SKIPPED", model_id, f"target already verified: {final_path}")
            return 0
        die(f"target exists but does not verify; refused overwrite: {detail}; {final_path}", 4)

    ok, detail = file_matches(source, expected, expected_size)
    if not ok:
        die(f"upload file does not match catalog: {detail}", 4)

    ensure_target_parent(final_path, model_id)
    shutil.move(str(source), str(final_path))
    ok, detail = ensure_auto_file_ok(final_path, expected, expected_size)
    if not ok:
        die(f"installed file failed verification: {detail}; {final_path}", 4)
    event("SUCCESS", model_id, str(final_path))
    return 0
