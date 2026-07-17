from __future__ import annotations

import subprocess
import textwrap
from pathlib import Path

from scripts.verify.common import (
    ROOT_DIR,
    VerifyContext,
    capture,
    die,
    env_value_from,
    expect_status,
    file_size,
    run,
    section,
    sha256_bytes,
    sha256_file,
    write_text,
)


def _contains(output: str, needle: str, message: str) -> None:
    if needle not in output:
        print(output)
        die(message, 1)


def run_config_and_models(ctx: VerifyContext) -> None:
    section("Config Contract Smoke")
    ctx.contract_profile = ctx.tmp_dir / "profile.env"
    write_text(
        ctx.contract_profile,
        textwrap.dedent(
            """\
            COMFY_PROFILE=verify-contract
            COMFY_ENV_BACKEND=uv
            COMFY_PYTHON=3.12.13
            COMFY_DEVICE=cpu
            COMFY_HOST=127.0.0.1
            COMFY_PORT=18188
            COMFY_MODEL_ROOT=/tmp/comfy-shell-profile-models
            COMFY_OUTPUT_ROOT=/tmp/comfy-shell-profile-output
            REMOTE_HOST=verify@example.com
            REMOTE_DIR=/tmp/comfy-shell-remote
            REMOTE_READY_URL=http://127.0.0.1:18188
            REMOTE_TUNNEL_LOCAL_PORT=18188
            REMOTE_TUNNEL_REMOTE_HOST=127.0.0.1
            REMOTE_TUNNEL_REMOTE_PORT=18189
            REMOTE_LOG_TAIL=42
            REMOTE_GPU_CONNECT_TIMEOUT=3
            """
        ),
    )

    if (ROOT_DIR / ".env").is_file():
        run([ROOT_DIR / "scripts/local.sh", "status"], env={"COMFY_DEVICE": "cpu"}, stdout=subprocess.DEVNULL)
        run([ROOT_DIR / "scripts/models.sh", "check"], stdout=subprocess.DEVNULL)
        run([ROOT_DIR / "scripts/models.sh", "plan", "heroine-i2v-core"], stdout=subprocess.DEVNULL)
        if env_value_from("REMOTE_HOST", ROOT_DIR / ".env") and env_value_from("REMOTE_DIR", ROOT_DIR / ".env"):
            run([ROOT_DIR / "scripts/remote.sh", "tunnel", "--dry-run"], stdout=subprocess.DEVNULL)
        else:
            from scripts.verify.common import event

            event("SKIP", "default-remote", ".env has no REMOTE_HOST/REMOTE_DIR")
    else:
        from scripts.verify.common import event

        event("SKIP", "default-.env", ".env not found")

    run([ROOT_DIR / "scripts/local.sh", "status", "--profile", ctx.contract_profile], stdout=subprocess.DEVNULL)
    runtime_python_profile = ctx.tmp_dir / "runtime-python.env"
    write_text(
        runtime_python_profile,
        textwrap.dedent(
            """\
            COMFY_PROFILE=verify-runtime-python
            COMFY_ENV_BACKEND=uv
            COMFY_PYTHON=3.12
            COMFY_DEVICE=cpu
            COMFY_HOST=127.0.0.1
            COMFY_PORT=18188
            COMFY_MODEL_ROOT=/tmp/comfy-shell-runtime-python-models
            COMFY_OUTPUT_ROOT=/tmp/comfy-shell-runtime-python-output
            """
        ),
    )
    run([ROOT_DIR / "scripts/local.sh", "status", "--profile", runtime_python_profile], stdout=subprocess.DEVNULL)

    plan = capture([ROOT_DIR / "scripts/models.sh", "plan", "heroine-i2v-core", "--profile", ctx.contract_profile])
    _contains(plan.stdout, "/tmp/comfy-shell-profile-models", "models.sh did not read COMFY_MODEL_ROOT from explicit --profile file")
    plan_env = capture(
        [ROOT_DIR / "scripts/models.sh", "plan", "heroine-i2v-core", "--profile", ctx.contract_profile],
        env={"COMFY_MODEL_ROOT": "/tmp/comfy-shell-env-models"},
    )
    _contains(plan_env.stdout, "/tmp/comfy-shell-env-models", "exported COMFY_MODEL_ROOT did not override explicit --profile file")
    run(
        [
            ROOT_DIR / "scripts/models.sh",
            "info",
            "--model",
            "isabelia-v10-checkpoint",
            "--profile",
            ctx.tmp_dir / "missing-model-profile.env",
        ],
        env={"COMFY_MODEL_ROOT": "/tmp/comfy-shell-env-without-profile-models"},
        stdout=subprocess.DEVNULL,
    )

    _run_hf_smoke(ctx)
    _run_civitai_download_smoke(ctx)
    _run_catalog_conflict_smoke(ctx)
    _run_status_and_schema_smoke(ctx)
    _run_missing_model_root_smoke(ctx)


def _run_hf_smoke(ctx: VerifyContext) -> None:
    hf_payload = b"model-data"
    hf_sha = sha256_bytes(hf_payload)
    hf_size = str(len(hf_payload))
    hf_catalog = ctx.tmp_dir / "hf-catalog.yaml"
    write_text(
        hf_catalog,
        f"""version: 2
bundles:
  hf-endpoint-smoke:
    title: HF endpoint smoke
    models:
      - id: endpoint-file
        directory: checkpoints
        filename: endpoint.bin
        source:
          platform: huggingface
          repo: smoke/repo
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: endpoint.bin
          sha256: {hf_sha}
          size_bytes: {hf_size}
""",
    )
    hf_profile = ctx.tmp_dir / "hf-profile.env"
    write_text(hf_profile, "COMFY_MODEL_ROOT=/tmp/comfy-shell-hf-endpoint-profile-models\nHF_ENDPOINT=https://profile.example\n")
    hf_stub_dir = ctx.tmp_dir / "hf-bin"
    hf_stub_dir.mkdir(parents=True, exist_ok=True)
    hf_stub = hf_stub_dir / "hf"
    write_text(
        hf_stub,
        """#!/usr/bin/env bash
[[ "${1:-}" == "download" ]] || exit 2
remote_path="${3:-}"
local_dir=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --local-dir)
      local_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$remote_path" && -n "$local_dir" ]] || exit 2
printf '%s\n' "${HF_ENDPOINT:-}" >"$COMFY_SHELL_HF_ENDPOINT_FILE"
mkdir -p "$local_dir/$(dirname "$remote_path")"
printf 'model-data' >"$local_dir/$remote_path"
""",
    )
    hf_stub.chmod(0o755)
    hf_endpoint_file = ctx.tmp_dir / "hf-endpoint.txt"
    for path in (Path("/tmp/comfy-shell-hf-endpoint-profile-models"), Path("/tmp/comfy-shell-hf-endpoint-env-models")):
        if path.exists():
            import shutil

            shutil.rmtree(path)
    run(
        [ROOT_DIR / "scripts/models.sh", "download", "hf-endpoint-smoke", "--profile", hf_profile],
        env={"COMFY_SHELL_HF_ENDPOINT_FILE": hf_endpoint_file, "CATALOG_FILE": hf_catalog, "HF_CLI": hf_stub},
        stdout=subprocess.DEVNULL,
    )
    if hf_endpoint_file.read_text(encoding="utf-8").strip() != "https://profile.example":
        die("models.sh download did not pass HF_ENDPOINT from profile to hf CLI", 1)
    run(
        [ROOT_DIR / "scripts/models.sh", "download", "hf-endpoint-smoke", "--profile", hf_profile],
        env={
            "COMFY_SHELL_HF_ENDPOINT_FILE": hf_endpoint_file,
            "CATALOG_FILE": hf_catalog,
            "HF_CLI": hf_stub,
            "COMFY_MODEL_ROOT": "/tmp/comfy-shell-hf-endpoint-env-models",
            "HF_ENDPOINT": "https://env.example",
        },
        stdout=subprocess.DEVNULL,
    )
    if hf_endpoint_file.read_text(encoding="utf-8").strip() != "https://env.example":
        die("exported HF_ENDPOINT did not override profile for hf CLI", 1)


def _run_civitai_download_smoke(ctx: VerifyContext) -> None:
    ctx.civitai_payload_file = ctx.tmp_dir / "civitai-payload.bin"
    ctx.civitai_payload_file.write_bytes(b"civitai-model-data")
    ctx.civitai_sha = sha256_file(ctx.civitai_payload_file)
    ctx.civitai_size = file_size(ctx.civitai_payload_file)
    ctx.civitai_catalog = ctx.tmp_dir / "civitai-catalog.yaml"
    write_text(
        ctx.civitai_catalog,
        f"""version: 2
bundles:
  civitai-smoke:
    title: Civitai smoke
    models:
      - id: civitai-file
        directory: loras
        filename: civitai.bin
        source:
          platform: civitai
          page_url: https://civitai.com/models/0/smoke
        download:
          mode: auto
          method: civitai
          url: file://{ctx.civitai_payload_file}
          sha256: {ctx.civitai_sha}
          size_bytes: {ctx.civitai_size}
      - id: manual-file
        directory: vae
        filename: manual.bin
        source:
          platform: unknown
        download:
          mode: manual
          reason: smoke manual entry
      - id: blocked-file
        directory: controlnet
        filename: blocked.bin
        source:
          platform: huggingface
          page_url: https://huggingface.co/smoke/repo
        download:
          mode: blocked
          reason: smoke blocked entry
""",
    )
    civitai_profile = ctx.tmp_dir / "civitai-profile.env"
    write_text(civitai_profile, "COMFY_MODEL_ROOT=/tmp/comfy-shell-civitai-profile-models\n")
    import shutil

    shutil.rmtree("/tmp/comfy-shell-civitai-profile-models", ignore_errors=True)
    stdout_file = ctx.tmp_dir / "civitai-download.stdout"
    stderr_file = ctx.tmp_dir / "civitai-download.stderr"
    with stdout_file.open("w", encoding="utf-8") as out, stderr_file.open("w", encoding="utf-8") as err:
        result = run(
            [ROOT_DIR / "scripts/models.sh", "download", "civitai-smoke", "--profile", civitai_profile],
            env={"CATALOG_FILE": ctx.civitai_catalog},
            stdout=out,
            stderr=err,
            check=False,
        )
    output = stdout_file.read_text(encoding="utf-8") + stderr_file.read_text(encoding="utf-8")
    if result.returncode != 0:
        print(output)
        die("models.sh download did not skip manual/blocked entries while auto succeeded", 1)
    if not Path("/tmp/comfy-shell-civitai-profile-models/loras/civitai.bin").is_file():
        die("models.sh download did not write civitai method target file", 1)
    stdout_text = stdout_file.read_text(encoding="utf-8")
    stderr_text = stderr_file.read_text(encoding="utf-8")
    for expected in ("success: 1", "manual: 1", "blocked: 1", "failed: 0"):
        _contains(stdout_text, expected, f"models.sh download summary missing: {expected}")
    _contains(stderr_text, "PROGRESS", "models.sh download did not print civitai download progress")
    _contains(stderr_text, "civitai-file", "models.sh download did not print civitai model progress")
    if "PROGRESS" in stdout_text:
        die("models.sh download printed progress to stdout instead of stderr", 1)

    single_profile = ctx.tmp_dir / "single-civitai-profile.env"
    write_text(single_profile, "COMFY_MODEL_ROOT=/tmp/comfy-shell-single-civitai-profile-models\n")
    shutil.rmtree("/tmp/comfy-shell-single-civitai-profile-models", ignore_errors=True)
    run(
        [ROOT_DIR / "scripts/models.sh", "download", "--model", "civitai-file", "--profile", single_profile],
        env={"CATALOG_FILE": ctx.civitai_catalog},
        stdout=subprocess.DEVNULL,
    )
    if not Path("/tmp/comfy-shell-single-civitai-profile-models/loras/civitai.bin").is_file():
        die("models.sh download --model did not write target file", 1)
    run(
        [ROOT_DIR / "scripts/models.sh", "verify", "--model", "civitai-file", "--profile", single_profile],
        env={"CATALOG_FILE": ctx.civitai_catalog},
        stdout=subprocess.DEVNULL,
    )
    expect_status(
        1,
        [ROOT_DIR / "scripts/models.sh", "download", "--model", "manual-file", "--profile", single_profile],
        env={"CATALOG_FILE": ctx.civitai_catalog},
    )

    blocked_root = ctx.tmp_dir / "not-a-directory-root"
    blocked_root.write_text("not a directory\n", encoding="utf-8")
    blocked_profile = ctx.tmp_dir / "blocked-model-root.env"
    write_text(blocked_profile, f"COMFY_MODEL_ROOT={blocked_root}/models\n")
    bad = capture(
        [ROOT_DIR / "scripts/models.sh", "download", "--model", "civitai-file", "--profile", blocked_profile],
        env={"CATALOG_FILE": ctx.civitai_catalog},
    )
    if bad.returncode != 4:
        print(bad.stdout + bad.stderr)
        die(f"models.sh download with unwritable COMFY_MODEL_ROOT returned {bad.returncode}, expected 4", 1)
    if "Traceback" in bad.stdout + bad.stderr:
        die("models.sh download with unwritable COMFY_MODEL_ROOT printed Python traceback", 1)
    _contains(bad.stderr + bad.stdout, "unable to create model target directory", "models.sh download with unwritable COMFY_MODEL_ROOT did not explain target directory failure")


def _run_catalog_conflict_smoke(ctx: VerifyContext) -> None:
    civitai_payload_file = ctx.civitai_payload_file
    if civitai_payload_file is None:
        die("internal verify context missing: civitai_payload_file", 1)

    duplicate_model_catalog = ctx.tmp_dir / "duplicate-model-catalog.yaml"
    write_text(
        duplicate_model_catalog,
        f"""version: 2
bundles:
  duplicate-a:
    title: Duplicate A
    models:
      - id: duplicate-model
        directory: loras
        filename: duplicate.bin
        source:
          platform: civitai
          page_url: https://civitai.com/models/1/duplicate
        download:
          mode: auto
          method: civitai
          url: file://{civitai_payload_file}
          sha256: {ctx.civitai_sha}
          size_bytes: {ctx.civitai_size}
  duplicate-b:
    title: Duplicate B
    models:
      - id: duplicate-model
        directory: loras
        filename: duplicate.bin
        source:
          platform: civitai
          page_url: https://civitai.com/models/2/duplicate
        download:
          mode: auto
          method: civitai
          url: file://{civitai_payload_file}?variant=2
          sha256: {ctx.civitai_sha}
          size_bytes: {ctx.civitai_size}
""",
    )
    profile = ctx.tmp_dir / "single-civitai-profile.env"
    duplicate_info = capture(
        [ROOT_DIR / "scripts/models.sh", "info", "--model", "duplicate-model", "--profile", profile],
        env={"CATALOG_FILE": duplicate_model_catalog},
    )
    duplicate_status = capture(
        [ROOT_DIR / "scripts/models.sh", "status", "--model", "duplicate-model", "--profile", profile],
        env={"CATALOG_FILE": duplicate_model_catalog},
    )
    if duplicate_info.returncode != 2 or duplicate_status.returncode != 2:
        print(duplicate_info.stdout + duplicate_info.stderr + duplicate_status.stdout + duplicate_status.stderr)
        die("models.sh --model accepted conflicting duplicate model declarations", 1)
    duplicate_output = duplicate_info.stdout + duplicate_info.stderr + duplicate_status.stdout + duplicate_status.stderr
    _contains(duplicate_output, "source.page_url differs:", "models.sh duplicate model conflict did not explain source.page_url mismatch")
    _contains(duplicate_output, "download.url differs:", "models.sh duplicate model conflict did not explain download.url mismatch")

    target_conflict_catalog = ctx.tmp_dir / "target-conflict-catalog.yaml"
    write_text(
        target_conflict_catalog,
        f"""version: 2
bundles:
  target-a:
    title: Target A
    models:
      - id: target-model-a
        directory: loras
        filename: shared-target.bin
        source:
          platform: civitai
          page_url: https://civitai.com/models/1/shared
        download:
          mode: auto
          method: civitai
          url: file://{civitai_payload_file}
          sha256: {ctx.civitai_sha}
          size_bytes: {ctx.civitai_size}
  target-b:
    title: Target B
    models:
      - id: target-model-b
        directory: loras
        filename: shared-target.bin
        source:
          platform: huggingface
          page_url: https://huggingface.co/smoke/shared
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/shared
          path: shared-target.bin
          sha256: "0000000000000000000000000000000000000000000000000000000000000000"
          size_bytes: {ctx.civitai_size}
""",
    )
    target_info = capture(
        [ROOT_DIR / "scripts/models.sh", "info", "--model", "target-model-a", "--profile", profile],
        env={"CATALOG_FILE": target_conflict_catalog},
    )
    target_status = capture(
        [ROOT_DIR / "scripts/models.sh", "status", "--model", "target-model-a", "--profile", profile],
        env={"CATALOG_FILE": target_conflict_catalog},
    )
    target_download = capture(
        [ROOT_DIR / "scripts/models.sh", "download", "--model", "target-model-a", "--profile", profile],
        env={"CATALOG_FILE": target_conflict_catalog},
    )
    if target_info.returncode != 2 or target_status.returncode != 2 or target_download.returncode != 2:
        print(
            target_info.stdout
            + target_info.stderr
            + target_status.stdout
            + target_status.stderr
            + target_download.stdout
            + target_download.stderr
        )
        die("models.sh --model accepted conflicting same-target declarations", 1)
    target_output = (
        target_info.stdout
        + target_info.stderr
        + target_status.stdout
        + target_status.stderr
        + target_download.stdout
        + target_download.stderr
    )
    _contains(
        target_output,
        "model target loras/shared-target.bin has conflicting catalog declarations",
        "models.sh same-target conflict did not explain target conflict",
    )


def _run_status_and_schema_smoke(ctx: VerifyContext) -> None:
    civitai_payload_file = ctx.civitai_payload_file
    if civitai_payload_file is None:
        die("internal verify context missing: civitai_payload_file", 1)

    status_smoke_root = ctx.tmp_dir / "status-models"
    (status_smoke_root / "checkpoints").mkdir(parents=True, exist_ok=True)
    (status_smoke_root / "loras").mkdir(parents=True, exist_ok=True)
    ok_file = status_smoke_root / "checkpoints/ok.bin"
    ok_file.write_bytes(b"model-data")
    status_ok_sha = sha256_file(ok_file)
    status_ok_size = file_size(ok_file)
    status_catalog = ctx.tmp_dir / "status-catalog.yaml"
    write_text(
        status_catalog,
        f"""version: 2
bundles:
  status-a:
    title: Status A
    models:
      - id: shared-ok-a
        directory: checkpoints
        filename: ok.bin
        source:
          platform: huggingface
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: ok.bin
          sha256: {status_ok_sha}
          size_bytes: {status_ok_size}
      - id: missing-file
        directory: checkpoints
        filename: missing.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: file://{civitai_payload_file}
          sha256: {ctx.civitai_sha}
      - id: manual-file
        directory: loras
        filename: manual.bin
        source:
          platform: unknown
        download:
          mode: manual
          reason: status manual entry
      - id: blocked-file
        directory: loras
        filename: blocked.bin
        source:
          platform: huggingface
        download:
          mode: blocked
          reason: status blocked entry
  status-b:
    title: Status B
    models:
      - id: shared-ok-b
        directory: checkpoints
        filename: ok.bin
        source:
          platform: huggingface
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: ok.bin
          sha256: {status_ok_sha}
          size_bytes: {status_ok_size}
""",
    )
    status_profile = ctx.tmp_dir / "status-profile.env"
    write_text(status_profile, f"COMFY_MODEL_ROOT={status_smoke_root}\n")
    status_smoke = capture(
        [ROOT_DIR / "scripts/models.sh", "status", "--profile", status_profile],
        env={"CATALOG_FILE": status_catalog},
    )
    if status_smoke.returncode != 1:
        print(status_smoke.stdout + status_smoke.stderr)
        die(f"models.sh status smoke returned {status_smoke.returncode}, expected 1", 1)
    for expected in ("ok: 1", "missing: 1", "manual: 1", "blocked: 1", "total_unique: 4", "bundles: status-a, status-b"):
        _contains(status_smoke.stdout + status_smoke.stderr, expected, f"models.sh status summary missing: {expected}")

    mixed_mode_catalog = ctx.tmp_dir / "mixed-mode-catalog.yaml"
    write_text(
        mixed_mode_catalog,
        f"""version: 2
bundles:
  mixed-manual:
    title: Mixed Manual
    models:
      - id: shared-manual
        directory: checkpoints
        filename: shared.bin
        source:
          platform: unknown
        download:
          mode: manual
          reason: mixed manual entry
  mixed-auto:
    title: Mixed Auto
    models:
      - id: shared-auto
        directory: checkpoints
        filename: shared.bin
        source:
          platform: huggingface
        download:
          mode: auto
          method: huggingface
          repo_type: model
          repo: smoke/repo
          path: shared.bin
          sha256: {status_ok_sha}
          size_bytes: {status_ok_size}
""",
    )
    mixed_mode = capture(
        [ROOT_DIR / "scripts/models.sh", "status", "--profile", status_profile],
        env={"CATALOG_FILE": mixed_mode_catalog},
    )
    if mixed_mode.returncode != 1:
        print(mixed_mode.stdout + mixed_mode.stderr)
        die(f"models.sh status mixed-mode target returned {mixed_mode.returncode}, expected 1", 1)
    mixed_output = mixed_mode.stdout + mixed_mode.stderr
    for expected in ("conflict: 1", "download.mode differs:", "auto", "manual"):
        _contains(mixed_output, expected, f"models.sh status mixed-mode output missing: {expected}")
    if "./scripts/models.sh download mixed-manual" in mixed_output:
        print(mixed_output)
        die("models.sh status suggested downloading the manual bundle for mixed target", 1)

    old_schema_catalog = ctx.tmp_dir / "old-schema-catalog.yaml"
    write_text(
        old_schema_catalog,
        f"""version: 1
bundles:
  old-schema:
    title: Old schema
    models:
      - id: old-file
        directory: checkpoints
        filename: old.bin
        source: huggingface
        repo: smoke/repo
        path: old.bin
        sha256: {ctx.civitai_sha}
""",
    )
    old_schema = capture([ROOT_DIR / "scripts/models.sh", "check"], env={"CATALOG_FILE": old_schema_catalog})
    if old_schema.returncode != 2:
        die("models.sh accepted old catalog schema, expected exit 2", 1)
    _contains(old_schema.stdout + old_schema.stderr, "version must be 2", "models.sh old schema rejection did not explain schema version")

    bad_civitai_url_catalog = ctx.tmp_dir / "bad-civitai-url-catalog.yaml"
    write_text(
        bad_civitai_url_catalog,
        f"""version: 2
bundles:
  bad-url:
    title: Bad URL
    models:
      - id: bad-url-file
        directory: loras
        filename: bad.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: not-a-url
          sha256: {ctx.civitai_sha}
""",
    )
    bad_url = capture([ROOT_DIR / "scripts/models.sh", "check"], env={"CATALOG_FILE": bad_civitai_url_catalog})
    if bad_url.returncode != 2:
        die("models.sh accepted bad civitai download.url, expected exit 2", 1)
    if "Traceback" in bad_url.stdout + bad_url.stderr:
        die("models.sh bad civitai download.url printed Python traceback", 1)

    bad_size_catalog = ctx.tmp_dir / "bad-size-catalog.yaml"
    write_text(
        bad_size_catalog,
        f"""version: 2
bundles:
  bad-size:
    title: Bad size
    models:
      - id: bad-size-file
        directory: loras
        filename: bad-size.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: file://{civitai_payload_file}
          sha256: {ctx.civitai_sha}
          size_bytes: nope
""",
    )
    bad_size = capture([ROOT_DIR / "scripts/models.sh", "check"], env={"CATALOG_FILE": bad_size_catalog})
    if bad_size.returncode != 2:
        die("models.sh accepted bad size_bytes, expected exit 2", 1)
    if "Traceback" in bad_size.stdout + bad_size.stderr:
        die("models.sh bad size_bytes printed Python traceback", 1)

    escaped_path_catalog = ctx.tmp_dir / "escaped-path-catalog.yaml"
    write_text(
        escaped_path_catalog,
        f"""version: 2
bundles:
  escaped-path:
    title: Escaped Path
    models:
      - id: escaped-file
        directory: ../escaped
        filename: escaped.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: file://{civitai_payload_file}
          sha256: {ctx.civitai_sha}
""",
    )
    escaped_path = capture([ROOT_DIR / "scripts/models.sh", "check"], env={"CATALOG_FILE": escaped_path_catalog})
    if escaped_path.returncode != 2:
        die("models.sh accepted model directory escaping COMFY_MODEL_ROOT, expected exit 2", 1)
    _contains(
        escaped_path.stdout + escaped_path.stderr,
        "directory must not contain empty, '.', or '..' path segments",
        "models.sh escaped directory rejection did not explain path segment rule",
    )

    escaped_filename_catalog = ctx.tmp_dir / "escaped-filename-catalog.yaml"
    write_text(
        escaped_filename_catalog,
        f"""version: 2
bundles:
  escaped-filename:
    title: Escaped Filename
    models:
      - id: escaped-filename
        directory: loras
        filename: ../escaped.bin
        source:
          platform: civitai
        download:
          mode: auto
          method: civitai
          url: file://{civitai_payload_file}
          sha256: {ctx.civitai_sha}
""",
    )
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "check"], env={"CATALOG_FILE": escaped_filename_catalog})

    manual_auto_key_catalog = ctx.tmp_dir / "manual-auto-key-catalog.yaml"
    write_text(
        manual_auto_key_catalog,
        """version: 2
bundles:
  manual-auto-key:
    title: Manual Auto Key
    models:
      - id: manual-auto-key
        directory: loras
        filename: manual.bin
        source:
          platform: unknown
        download:
          mode: manual
          method: browser
          reason: manual entries must not keep auto-only keys
""",
    )
    manual_auto_key = capture([ROOT_DIR / "scripts/models.sh", "check"], env={"CATALOG_FILE": manual_auto_key_catalog})
    if manual_auto_key.returncode != 2:
        die("models.sh accepted auto-only download keys on manual entry, expected exit 2", 1)
    _contains(
        manual_auto_key.stdout + manual_auto_key.stderr,
        "uses auto-only keys with mode=manual",
        "models.sh manual auto-key rejection did not explain mode mismatch",
    )


def _run_missing_model_root_smoke(ctx: VerifyContext) -> None:
    missing_model_profile = ctx.tmp_dir / "no-model-root.env"
    write_text(
        missing_model_profile,
        textwrap.dedent(
            """\
            COMFY_PROFILE=verify-missing-model-root
            COMFY_ENV_BACKEND=uv
            COMFY_PYTHON=3.12.13
            COMFY_DEVICE=cpu
            COMFY_HOST=127.0.0.1
            COMFY_PORT=18188
            COMFY_OUTPUT_ROOT=/tmp/comfy-shell-missing-model-output
            """
        ),
    )
    run([ROOT_DIR / "scripts/models.sh", "list"], stdout=subprocess.DEVNULL)
    run([ROOT_DIR / "scripts/models.sh", "check"], stdout=subprocess.DEVNULL)
    missing_model = capture([ROOT_DIR / "scripts/models.sh", "plan", "heroine-i2v-core", "--profile", missing_model_profile])
    if missing_model.returncode != 2:
        die(f"models.sh plan without COMFY_MODEL_ROOT returned {missing_model.returncode}, expected 2", 1)
    if any(line.startswith("target:") for line in (missing_model.stdout + missing_model.stderr).splitlines()):
        die("models.sh plan without COMFY_MODEL_ROOT printed a target path", 1)
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "status", "--profile", missing_model_profile])
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "download", "heroine-i2v-core", "--profile", missing_model_profile])
