from __future__ import annotations

import os
import subprocess
from pathlib import Path

from scripts.verify.common import (
    ROOT_DIR,
    VerifyContext,
    capture,
    chmod_x,
    die,
    expect_status,
    file_size,
    remote_model_helper_output,
    run,
    section,
    sha256_file,
    write_text,
)


def _require_path(value: Path | None, label: str) -> Path:
    if value is None:
        die(f"internal verify context missing: {label}", 1)
    return value


def _contains(text: str, needle: str, message: str) -> None:
    if needle not in text:
        print(text)
        die(message, 1)


def _not_contains(text: str, needle: str, message: str) -> None:
    if needle in text:
        print(text)
        die(message, 1)


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _contains_file(path: Path, needle: str, message: str) -> None:
    _contains(_read(path), needle, message)


def _contains_file_line(path: Path, needle: str, message: str) -> None:
    if needle not in _read(path).splitlines():
        print(_read(path))
        die(message, 1)


def _stub_env(stub_dir: Path, **extra: str | Path) -> dict[str, str]:
    env = {
        "PATH": f"{stub_dir}{os.pathsep}{os.environ.get('PATH', '')}",
    }
    env.update({key: str(value) for key, value in extra.items()})
    return env


def _run_remote_with_stub(
    stub_dir: Path,
    ssh_argv_file: Path,
    args: list[str | Path],
    *,
    env: dict[str, str | Path] | None = None,
) -> None:
    merged = _stub_env(stub_dir, COMFY_SHELL_SSH_ARGV_FILE=ssh_argv_file)
    if env:
        merged.update({key: str(value) for key, value in env.items()})
    run([ROOT_DIR / "scripts/remote.sh", *args], env=merged, stdout=subprocess.DEVNULL)


def run_remote_contract(ctx: VerifyContext) -> None:
    section("Remote Contract Smoke")
    contract_profile = _require_path(ctx.contract_profile, "contract_profile")
    civitai_catalog = _require_path(ctx.civitai_catalog, "civitai_catalog")
    civitai_payload_file = _require_path(ctx.civitai_payload_file, "civitai_payload_file")
    if not ctx.civitai_sha:
        die("internal verify context missing: civitai_sha", 1)
    if not ctx.civitai_size:
        die("internal verify context missing: civitai_size", 1)

    _run_argument_protection(ctx, contract_profile)

    stub_dir = ctx.tmp_dir / "remote-contract-bin"
    ssh_argv_file = ctx.tmp_dir / "ssh-argv.txt"
    rsync_argv_file = ctx.tmp_dir / "rsync-argv.txt"
    _write_remote_stubs(stub_dir)

    _run_models_command_contracts(stub_dir, ssh_argv_file, contract_profile)
    _run_catalog_upload_contract(
        ctx,
        stub_dir,
        ssh_argv_file,
        rsync_argv_file,
        contract_profile,
        civitai_catalog,
        civitai_payload_file,
    )
    _run_upload_file_contract(ctx, stub_dir, ssh_argv_file, rsync_argv_file, contract_profile)
    _run_upload_file_prepare_contract(ctx)
    _run_missing_remote_contract(ctx)
    _run_tunnel_contract(ctx, contract_profile)


def _run_argument_protection(ctx: VerifyContext, contract_profile: Path) -> None:
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "bootstrap", "--profile", contract_profile])
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "sync", "--profile", contract_profile])
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "tunnel", "--profile", ctx.tmp_dir / "missing.env", "--dry-run"])
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/remote.sh",
            "models",
            "plan",
            "retro-anime-photo-core",
            "--profile",
            contract_profile,
        ],
    )
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/remote.sh",
            "models",
            "--profile",
            contract_profile,
            "check",
            "retro-anime-photo-core",
        ],
    )


def _write_remote_stubs(stub_dir: Path) -> None:
    stub_dir.mkdir(parents=True, exist_ok=True)
    ssh_stub = stub_dir / "ssh"
    write_text(
        ssh_stub,
        """#!/usr/bin/env bash
printf '%s\n' "$@" >"$COMFY_SHELL_SSH_ARGV_FILE"
if [[ "$*" == *"./scripts/models.sh info --model civitai-file"* ]]; then
  printf 'id\tcivitai-file\n'
  printf 'bundles\tcivitai-smoke\n'
  printf 'target\tloras/civitai.bin\n'
  printf 'path\t%s\n' "$COMFY_SHELL_UPLOAD_REMOTE_PATH"
  printf 'directory\tloras\n'
  printf 'filename\tcivitai.bin\n'
  printf 'mode\tauto\n'
  printf 'method\tcivitai\n'
  printf 'sha256\t%s\n' "$COMFY_SHELL_UPLOAD_SHA"
  printf 'size_bytes\t%s\n' "$COMFY_SHELL_UPLOAD_SIZE"
  printf 'source\tcivitai page=https://civitai.com/models/0/smoke\n'
fi
if [[ "$*" == *"models-upload-file-prepare"* ]]; then
  printf 'ROOT\t%s\n' "$COMFY_SHELL_UPLOAD_FILE_REMOTE_ROOT"
  printf 'TARGET\t%s\n' "$COMFY_SHELL_UPLOAD_FILE_REMOTE_PATH"
  printf 'TMP\t%s\n' "$COMFY_SHELL_UPLOAD_FILE_REMOTE_TMP"
fi
""",
    )
    chmod_x(ssh_stub)

    rsync_stub = stub_dir / "rsync"
    write_text(
        rsync_stub,
        """#!/usr/bin/env bash
printf '%s\n' "$@" >"$COMFY_SHELL_RSYNC_ARGV_FILE"
""",
    )
    chmod_x(rsync_stub)


def _run_models_command_contracts(stub_dir: Path, ssh_argv_file: Path, contract_profile: Path) -> None:
    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "check"],
    )
    _contains_file_line(
        ssh_argv_file,
        "cd /tmp/comfy-shell-remote && ./scripts/models.sh check",
        "remote.sh models check did not build the expected remote models.sh command",
    )

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "plan", "retro-anime-photo-core"],
    )
    _contains_file_line(ssh_argv_file, "verify@example.com", "remote.sh models did not pass configured REMOTE_HOST to ssh")
    _contains_file_line(
        ssh_argv_file,
        "cd /tmp/comfy-shell-remote && ./scripts/models.sh plan retro-anime-photo-core",
        "remote.sh models did not build the expected remote models.sh command",
    )

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "status", "--model", "isabelia-v10-checkpoint"],
    )
    _contains_file_line(
        ssh_argv_file,
        "cd /tmp/comfy-shell-remote && ./scripts/models.sh status --model isabelia-v10-checkpoint",
        "remote.sh models did not build the expected remote models.sh --model command",
    )

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "download", "retro-anime-photo-core", "--detach"],
    )
    _contains_file(ssh_argv_file, "nohup sh -c", "remote.sh models download --detach did not build a nohup shell wrapper")
    _contains_file(
        ssh_argv_file,
        "./scripts/models.sh download retro-anime-photo-core",
        "remote.sh models download --detach did not keep the remote models.sh download argv",
    )
    _contains_file(
        ssh_argv_file,
        "models-download .run/models-download-retro-anime-photo-core.pid",
        "remote.sh models download --detach did not tag the remote process with the bundle",
    )
    _contains_file(
        ssh_argv_file,
        ".run/models-download-retro-anime-photo-core.pid",
        "remote.sh models download --detach did not write the expected pid path",
    )
    _contains_file(
        ssh_argv_file,
        "logs/models-download-retro-anime-photo-core.log",
        "remote.sh models download --detach did not write the expected log path",
    )

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "download", "--model", "isabelia-v10-checkpoint", "--detach"],
    )
    _contains_file(
        ssh_argv_file,
        "./scripts/models.sh download --model isabelia-v10-checkpoint",
        "remote.sh models download --model --detach did not keep the remote models.sh argv",
    )
    _contains_file(
        ssh_argv_file,
        ".run/models-download-model-isabelia-v10-checkpoint.pid",
        "remote.sh models download --model --detach did not write the expected pid path",
    )
    _contains_file(
        ssh_argv_file,
        "logs/models-download-model-isabelia-v10-checkpoint.log",
        "remote.sh models download --model --detach did not write the expected log path",
    )

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "logs", "retro-anime-photo-core"],
    )
    _contains_file_line(
        ssh_argv_file,
        'cd /tmp/comfy-shell-remote && if [ ! -f logs/models-download-retro-anime-photo-core.log ]; then printf "ERROR: remote model log not found: logs/models-download-retro-anime-photo-core.log\\n" >&2; exit 2; fi; tail -n 42 logs/models-download-retro-anime-photo-core.log',
        "remote.sh models logs did not use REMOTE_LOG_TAIL from profile",
    )

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "logs", "retro-anime-photo-core", "--tail", "all", "--follow"],
    )
    _contains_file_line(
        ssh_argv_file,
        'cd /tmp/comfy-shell-remote && if [ ! -f logs/models-download-retro-anime-photo-core.log ]; then printf "ERROR: remote model log not found: logs/models-download-retro-anime-photo-core.log\\n" >&2; exit 2; fi; tail -n +1 -F logs/models-download-retro-anime-photo-core.log',
        "remote.sh models logs --tail all --follow did not build the expected tail command",
    )

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "logs", "--model", "isabelia-v10-checkpoint", "--tail", "all", "--follow"],
    )
    _contains_file_line(
        ssh_argv_file,
        'cd /tmp/comfy-shell-remote && if [ ! -f logs/models-download-model-isabelia-v10-checkpoint.log ]; then printf "ERROR: remote model log not found: logs/models-download-model-isabelia-v10-checkpoint.log\\n" >&2; exit 2; fi; tail -n +1 -F logs/models-download-model-isabelia-v10-checkpoint.log',
        "remote.sh models logs --model --tail all --follow did not build the expected tail command",
    )


def _run_catalog_upload_contract(
    ctx: VerifyContext,
    stub_dir: Path,
    ssh_argv_file: Path,
    rsync_argv_file: Path,
    contract_profile: Path,
    civitai_catalog: Path,
    civitai_payload_file: Path,
) -> None:
    upload_root = ctx.tmp_dir / "upload-model-root"
    upload_target = upload_root / "loras" / "civitai.bin"
    upload_target.parent.mkdir(parents=True, exist_ok=True)
    upload_target.write_bytes(civitai_payload_file.read_bytes())
    upload_remote_path = "/tmp/comfy-shell-remote-models/loras/civitai.bin"
    env = {
        "COMFY_MODEL_ROOT": upload_root,
        "CATALOG_FILE": civitai_catalog,
        "COMFY_SHELL_RSYNC_ARGV_FILE": rsync_argv_file,
        "COMFY_SHELL_UPLOAD_REMOTE_PATH": upload_remote_path,
        "COMFY_SHELL_UPLOAD_SHA": ctx.civitai_sha,
        "COMFY_SHELL_UPLOAD_SIZE": ctx.civitai_size,
    }
    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "upload", "--model", "civitai-file"],
        env=env,
    )
    _contains_file(
        rsync_argv_file,
        str(upload_target),
        "remote.sh models upload did not rsync the local verified model file",
    )
    _contains_file(
        rsync_argv_file,
        "verify@example.com:/tmp/comfy-shell-remote-models/loras/.civitai.bin.upload.civitai-file.",
        "remote.sh models upload did not rsync to the expected remote temp target",
    )
    _contains_file(
        ssh_argv_file,
        "tmp_path=/tmp/comfy-shell-remote-models/loras/.civitai.bin.upload.civitai-file.",
        "remote.sh models upload did not set remote temp path",
    )
    _contains_file(
        ssh_argv_file,
        './scripts/models.sh install-upload --model civitai-file --file "$tmp_path"',
        "remote.sh models upload did not call remote install-upload",
    )

    mismatch = capture(
        [ROOT_DIR / "scripts/remote.sh", "models", "--profile", contract_profile, "upload", "--model", "civitai-file"],
        env=_stub_env(
            stub_dir,
            COMFY_SHELL_SSH_ARGV_FILE=ssh_argv_file,
            COMFY_SHELL_RSYNC_ARGV_FILE=rsync_argv_file,
            COMFY_MODEL_ROOT=upload_root,
            CATALOG_FILE=civitai_catalog,
            COMFY_SHELL_UPLOAD_REMOTE_PATH=upload_remote_path,
            COMFY_SHELL_UPLOAD_SHA="0" * 64,
            COMFY_SHELL_UPLOAD_SIZE=ctx.civitai_size,
        ),
    )
    if mismatch.returncode != 2:
        print(mismatch.stdout + mismatch.stderr)
        die(f"remote.sh models upload accepted local/remote catalog sha256 mismatch: {mismatch.returncode}", 1)
    _contains(
        mismatch.stdout + mismatch.stderr,
        "local and remote catalog sha256 differ",
        "remote.sh models upload mismatch did not explain sha256 mismatch",
    )


def _run_upload_file_contract(
    ctx: VerifyContext,
    stub_dir: Path,
    ssh_argv_file: Path,
    rsync_argv_file: Path,
    contract_profile: Path,
) -> None:
    upload_file_source = (ctx.tmp_dir / "manual-upload.safetensors").resolve(strict=False)
    write_text(upload_file_source, "manual-upload-model-data")
    upload_file_remote_root = "/tmp/comfy-shell-remote-models"
    upload_file_remote_path = "/tmp/comfy-shell-remote-models/loras/manual-upload.safetensors"
    upload_file_remote_tmp = "/tmp/comfy-shell-remote-models/loras/.manual-upload.safetensors.upload-file.12345"

    _run_remote_with_stub(
        stub_dir,
        ssh_argv_file,
        ["models", "--profile", contract_profile, "upload-file", "--file", upload_file_source, "--to", "loras"],
        env={
            "COMFY_SHELL_RSYNC_ARGV_FILE": rsync_argv_file,
            "COMFY_SHELL_UPLOAD_FILE_REMOTE_ROOT": upload_file_remote_root,
            "COMFY_SHELL_UPLOAD_FILE_REMOTE_PATH": upload_file_remote_path,
            "COMFY_SHELL_UPLOAD_FILE_REMOTE_TMP": upload_file_remote_tmp,
        },
    )
    _contains_file(
        rsync_argv_file,
        str(upload_file_source),
        "remote.sh models upload-file did not rsync the requested local file",
    )
    _contains_file(
        rsync_argv_file,
        f"verify@example.com:{upload_file_remote_tmp}",
        "remote.sh models upload-file did not rsync to the remote temp target",
    )
    _contains_file(
        ssh_argv_file,
        "models-upload-file-install",
        "remote.sh models upload-file did not build the remote install command",
    )
    _contains_file(
        ssh_argv_file,
        upload_file_remote_path,
        "remote.sh models upload-file install command did not include target path",
    )
    _contains_file(
        ssh_argv_file,
        upload_file_remote_tmp,
        "remote.sh models upload-file install command did not include temp path",
    )
    _not_contains(
        _read(ssh_argv_file),
        "./scripts/models.sh install-upload",
        "remote.sh models upload-file should not call catalog install-upload",
    )


def _run_upload_file_prepare_contract(ctx: VerifyContext) -> None:
    upload_file_source = ctx.tmp_dir / "manual-upload.safetensors"
    upload_file_sha = sha256_file(upload_file_source)
    upload_file_size = file_size(upload_file_source)

    remote_checkout = ctx.tmp_dir / "upload-file-remote-checkout"
    remote_model_root = ctx.tmp_dir / "upload-file-model-root"
    remote_target = remote_model_root / "loras" / "manual-upload.safetensors"
    remote_target.parent.mkdir(parents=True, exist_ok=True)
    remote_checkout.mkdir(parents=True, exist_ok=True)
    write_text(remote_checkout / ".env", f"COMFY_MODEL_ROOT={remote_model_root}\n")
    write_text(remote_target, "manual-upload-model-data")

    skip = _run_upload_file_prepare_cmd(remote_checkout, upload_file_sha, upload_file_size)
    if skip.returncode != 0 or not skip.stdout.startswith("SKIPPED\t"):
        print(skip.stdout + skip.stderr)
        die("remote upload-file prepare did not skip identical existing target", 1)

    write_text(remote_target, "different-model-data")
    conflict = _run_upload_file_prepare_cmd(remote_checkout, upload_file_sha, upload_file_size)
    if conflict.returncode != 4:
        print(conflict.stdout + conflict.stderr)
        die("remote upload-file prepare did not reject different existing target", 1)
    _contains(
        conflict.stdout + conflict.stderr,
        "remote target exists with different content",
        "remote upload-file conflict did not explain existing target mismatch",
    )

    missing_root_checkout = ctx.tmp_dir / "upload-file-missing-root-checkout"
    missing_root_checkout.mkdir(parents=True, exist_ok=True)
    missing_root = _run_upload_file_prepare_cmd(missing_root_checkout, upload_file_sha, upload_file_size)
    if missing_root.returncode != 2:
        print(missing_root.stdout + missing_root.stderr)
        die(f"remote upload-file prepare without COMFY_MODEL_ROOT returned {missing_root.returncode}, expected 2", 1)
    _contains(
        missing_root.stdout + missing_root.stderr,
        "COMFY_MODEL_ROOT is required",
        "remote upload-file missing COMFY_MODEL_ROOT did not explain the missing config",
    )

    escape_root = ctx.tmp_dir / "upload-file-escape-root"
    escape_outside = ctx.tmp_dir / "upload-file-escape-outside"
    escape_checkout = ctx.tmp_dir / "upload-file-escape-checkout"
    escape_root.mkdir(parents=True, exist_ok=True)
    escape_outside.mkdir(parents=True, exist_ok=True)
    escape_checkout.mkdir(parents=True, exist_ok=True)
    (escape_root / "loras").symlink_to(escape_outside)
    write_text(escape_checkout / ".env", f"COMFY_MODEL_ROOT={escape_root}\n")
    escaped = _run_upload_file_prepare_cmd(escape_checkout, upload_file_sha, upload_file_size)
    if escaped.returncode != 4:
        print(escaped.stdout + escaped.stderr)
        die("remote upload-file prepare did not reject symlink escape", 1)
    _contains(
        escaped.stdout + escaped.stderr,
        "upload path escapes COMFY_MODEL_ROOT",
        "remote upload-file symlink escape did not explain path containment failure",
    )


def _run_upload_file_prepare_cmd(checkout: Path, expected_sha: str, expected_size: str) -> subprocess.CompletedProcess[str]:
    command = remote_model_helper_output(
        "remote_models_upload_file_prepare_cmd",
        [checkout, "loras", "manual-upload.safetensors", expected_sha, expected_size],
    )
    return capture(["bash", "-c", command])


def _run_missing_remote_contract(ctx: VerifyContext) -> None:
    missing_remote_profile = ctx.tmp_dir / "no-remote.env"
    write_text(
        missing_remote_profile,
        """COMFY_PROFILE=verify-missing-remote
COMFY_ENV_BACKEND=uv
COMFY_PYTHON=3.12.13
COMFY_DEVICE=cpu
COMFY_HOST=127.0.0.1
COMFY_PORT=18188
COMFY_MODEL_ROOT=/tmp/comfy-shell-missing-remote-models
COMFY_OUTPUT_ROOT=/tmp/comfy-shell-missing-remote-output
""",
    )

    missing_remote = capture([ROOT_DIR / "scripts/remote.sh", "status", "--profile", missing_remote_profile])
    if missing_remote.returncode != 2:
        die(f"remote.sh missing REMOTE_* returned {missing_remote.returncode}, expected 2", 1)
    _contains(
        missing_remote.stdout + missing_remote.stderr,
        "REMOTE_HOST, REMOTE_DIR are not configured",
        "remote.sh missing REMOTE_* did not explain missing keys",
    )
    _not_contains(
        missing_remote.stdout + missing_remote.stderr,
        "用法:",
        "remote.sh missing REMOTE_* printed full usage instead of concise config guidance",
    )

    missing_host = capture([ROOT_DIR / "scripts/remote.sh", "tunnel", "--profile", missing_remote_profile, "--dry-run"])
    if missing_host.returncode != 2:
        die(f"remote.sh missing REMOTE_HOST returned {missing_host.returncode}, expected 2", 1)
    _contains(
        missing_host.stdout + missing_host.stderr,
        "REMOTE_HOST is not configured",
        "remote.sh host-only missing REMOTE_HOST did not explain missing key",
    )
    _not_contains(
        missing_host.stdout + missing_host.stderr,
        "用法:",
        "remote.sh host-only missing REMOTE_HOST printed full usage instead of concise config guidance",
    )

    missing_models = capture(
        [ROOT_DIR / "scripts/remote.sh", "models", "--profile", missing_remote_profile, "plan", "retro-anime-photo-core"]
    )
    if missing_models.returncode != 2:
        die(f"remote.sh models missing REMOTE_* returned {missing_models.returncode}, expected 2", 1)
    _contains(
        missing_models.stdout + missing_models.stderr,
        "REMOTE_HOST, REMOTE_DIR are not configured",
        "remote.sh models missing REMOTE_* did not explain missing keys",
    )


def _run_tunnel_contract(ctx: VerifyContext, contract_profile: Path) -> None:
    tunnel = capture([ROOT_DIR / "scripts/remote.sh", "tunnel", "--profile", contract_profile, "--dry-run"])
    if tunnel.returncode != 0:
        print(tunnel.stdout + tunnel.stderr)
        die(f"remote.sh tunnel --dry-run returned {tunnel.returncode}, expected 0", 1)
    _contains(
        tunnel.stdout + tunnel.stderr,
        "18188:127.0.0.1:18189",
        "remote.sh did not read REMOTE_TUNNEL_* from explicit --profile file",
    )

    tunnel_env = capture(
        [ROOT_DIR / "scripts/remote.sh", "tunnel", "--profile", contract_profile, "--dry-run"],
        env={"REMOTE_TUNNEL_LOCAL_PORT": "18190"},
    )
    if tunnel_env.returncode != 0:
        print(tunnel_env.stdout + tunnel_env.stderr)
        die(f"remote.sh tunnel env override returned {tunnel_env.returncode}, expected 0", 1)
    _contains(
        tunnel_env.stdout + tunnel_env.stderr,
        "18190:127.0.0.1:18189",
        "exported REMOTE_TUNNEL_LOCAL_PORT did not override explicit --profile file",
    )

    tunnel_cli = capture(
        [
            ROOT_DIR / "scripts/remote.sh",
            "tunnel",
            "--profile",
            contract_profile,
            "--host",
            "override@example.com",
            "--local-port",
            "18191",
            "--remote-host",
            "localhost",
            "--remote-port",
            "18192",
            "--dry-run",
        ]
    )
    if tunnel_cli.returncode != 0:
        print(tunnel_cli.stdout + tunnel_cli.stderr)
        die(f"remote.sh tunnel CLI override returned {tunnel_cli.returncode}, expected 0", 1)
    _contains(
        tunnel_cli.stdout + tunnel_cli.stderr,
        "18191:localhost:18192 override@example.com",
        "remote.sh CLI tunnel overrides did not win over profile config",
    )
