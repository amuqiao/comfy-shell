from __future__ import annotations

import subprocess
import sys

from scripts.verify.common import ROOT_DIR, capture, die, expect_status, section, write_text


def run_read_only(ctx) -> None:
    section("Read-only Smoke")
    run_env = {"COMFY_DEVICE": "cpu"}
    from scripts.verify.common import run

    run([ROOT_DIR / "scripts/check_env.sh", "--no-network"], env=run_env, stdout=subprocess.DEVNULL)
    run(
        [ROOT_DIR / "scripts/check_env.sh", "--profile", ".env.example", "--no-network"],
        env=run_env,
        stdout=subprocess.DEVNULL,
    )
    run([ROOT_DIR / "scripts/models.sh", "check"], stdout=subprocess.DEVNULL)
    run([ROOT_DIR / "scripts/models.sh", "check"], env={"COMFY_MODEL_ROOT": ""}, stdout=subprocess.DEVNULL)
    run([ROOT_DIR / "scripts/models.sh", "list"], stdout=subprocess.DEVNULL)
    run([ROOT_DIR / "scripts/models.sh", "list-models", "retro-anime-photo-core"], stdout=subprocess.DEVNULL)
    run(
        [
            ROOT_DIR / "scripts/models.sh",
            "inspect",
            ROOT_DIR / ".data/nodes/批量照片转绘复古动漫风格（LoRA+ControlNet+UltimateSDUpscale）.png",
        ],
        stdout=subprocess.DEVNULL,
    )

    bad_workflow_file = ctx.tmp_dir / "bad-workflow.json"
    write_text(bad_workflow_file, "{bad-json\n")
    bad = capture([ROOT_DIR / "scripts/models.sh", "inspect", bad_workflow_file])
    if bad.returncode != 2:
        die(f"models.sh inspect bad workflow returned {bad.returncode}, expected 2", 1)
    if "Traceback" in bad.stderr or "Traceback" in bad.stdout:
        die("models.sh inspect bad workflow printed Python traceback", 1)

    read_only_model_root = ctx.tmp_dir / "read-only-models"
    (read_only_model_root / "loras").mkdir(parents=True, exist_ok=True)
    (read_only_model_root / "loras/read-only.safetensors").write_bytes(b"read-only-model")
    read_only_model_profile = ctx.tmp_dir / "read-only-model-profile.env"
    write_text(read_only_model_profile, f"COMFY_MODEL_ROOT={read_only_model_root}\n")
    run([ROOT_DIR / "scripts/models.sh", "inventory", "--profile", read_only_model_profile], stdout=subprocess.DEVNULL)
    run([ROOT_DIR / "scripts/models.sh", "plan", "heroine-i2v-core", "--profile", read_only_model_profile], stdout=subprocess.DEVNULL)
    run([ROOT_DIR / "scripts/models.sh", "plan", "retro-anime-photo-core", "--profile", read_only_model_profile], stdout=subprocess.DEVNULL)
    run(
        [
            ROOT_DIR / "scripts/models.sh",
            "plan",
            "--model",
            "isabelia-v10-checkpoint",
            "--profile",
            read_only_model_profile,
        ],
        stdout=subprocess.DEVNULL,
    )
    run(
        [
            ROOT_DIR / "scripts/models.sh",
            "info",
            "--model",
            "isabelia-v10-checkpoint",
            "--profile",
            read_only_model_profile,
        ],
        stdout=subprocess.DEVNULL,
    )
    expect_status(1, [ROOT_DIR / "scripts/models.sh", "verify", "retro-anime-photo-core", "--profile", read_only_model_profile])
    expect_status(
        1,
        [
            ROOT_DIR / "scripts/models.sh",
            "verify",
            "--model",
            "isabelia-v10-checkpoint",
            "--profile",
            read_only_model_profile,
        ],
    )
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/models.sh",
            "catalog-status",
            "--model",
            "isabelia-v10-checkpoint",
            "--model",
            "retro-anime-lora",
            "--profile",
            read_only_model_profile,
        ],
    )
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "download"])
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "check", "--profile", read_only_model_profile])
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "check", "retro-anime-photo-core"])
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "list", "--profile", read_only_model_profile])
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "list-models", "--profile", read_only_model_profile])
    expect_status(2, [ROOT_DIR / "scripts/models.sh", "inventory", "retro-anime-photo-core", "--profile", read_only_model_profile])

    run(
        [
            ROOT_DIR / "scripts/remote.sh",
            "tunnel",
            "--profile",
            ".env.example",
            "--local-port",
            "18188",
            "--dry-run",
        ],
        stdout=subprocess.DEVNULL,
    )
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "models", "--profile", ".env.example", "inspect", ".data/nodes/workflow.png"])
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "models", "--profile", ".env.example", "logs"])
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/remote.sh",
            "models",
            "--profile",
            ".env.example",
            "logs",
            "retro-anime-photo-core",
            "--tail",
            "nope",
        ],
    )
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/remote.sh",
            "models",
            "--profile",
            ".env.example",
            "logs",
            "retro-anime-photo-core",
            "--tail",
        ],
    )
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "models", "--profile", ".env.example", "plan", "retro-anime-photo-core", "--detach"])
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/remote.sh",
            "models",
            "--profile",
            ".env.example",
            "download",
            "retro-anime-photo-core",
            "--profile",
            ".env.example",
        ],
    )
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "models", "--profile", ".env.example", "upload", "retro-anime-photo-core"])
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "models", "--profile", ".env.example", "upload-file"])
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "models", "--profile", ".env.example", "upload-file", "--file", "/tmp/missing-model.bin"])
    for bad_to in ("../loras", "/tmp/loras", "loras//bad"):
        expect_status(
            2,
            [
                ROOT_DIR / "scripts/remote.sh",
                "models",
                "--profile",
                ".env.example",
                "upload-file",
                "--file",
                "/tmp/missing-model.bin",
                "--to",
                bad_to,
            ],
        )
    for bad_name in ("../bad.bin", "bad/name.bin", "."):
        expect_status(
            2,
            [
                ROOT_DIR / "scripts/remote.sh",
                "models",
                "--profile",
                ".env.example",
                "upload-file",
                "--file",
                "/tmp/missing-model.bin",
                "--to",
                "loras",
                "--name",
                bad_name,
            ],
        )
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/remote.sh",
            "models",
            "--profile",
            ".env.example",
            "upload-file",
            "--file",
            "/tmp/missing-model.bin",
            "--to",
            "loras",
            "--detach",
        ],
    )
    expect_status(
        2,
        [
            ROOT_DIR / "scripts/remote.sh",
            "models",
            "--profile",
            ".env.example",
            "upload-file",
            "--file",
            "/tmp/missing-model.bin",
            "--to",
            "loras",
            "--model",
            "civitai-file",
        ],
    )
    expect_status(2, [ROOT_DIR / "scripts/local.sh", "status", "--unknown"])
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "sync", "--profile", ".env.example"])
    expect_status(2, [ROOT_DIR / "scripts/remote.sh", "status", "--profile", ".env.example", "--unknown"])

    try:
        empty_gpu = subprocess.run(
            [sys.executable, str(ROOT_DIR / "scripts/lib/remote_gpu_format.py"), "--host", "smoke", "--json"],
            input="",
            cwd=ROOT_DIR,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError as exc:
        die(f"unable to run remote_gpu_format.py smoke: {exc}", 4)
    if empty_gpu.returncode == 0:
        die("remote_gpu_format.py accepted an empty snapshot", 1)
