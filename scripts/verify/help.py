from __future__ import annotations

import subprocess

from scripts.verify.common import ROOT_DIR, capture, die, section, run


def _help_contains(argv: list, expected: tuple[str, ...], message: str) -> None:
    result = capture(argv)
    if result.returncode != 0:
        die(f"help command failed ({result.returncode}): {' '.join(str(part) for part in argv)}", result.returncode)
    output = result.stdout + result.stderr
    for needle in expected:
        if needle not in output:
            print(output)
            die(f"{message}: missing {needle}", 1)


def run_help() -> None:
    section("Help Smoke")
    for entry in (
        "check_env.sh",
        "local.sh",
        "nodes.sh",
        "models.sh",
        "remote.sh",
        "verify.sh",
    ):
        run([ROOT_DIR / "scripts" / entry, "-h"], stdout=subprocess.DEVNULL)
    run([ROOT_DIR / "tools/create-shell-submodule.sh", "-h"], stdout=subprocess.DEVNULL)

    for subcmd in ("bootstrap", "start", "stop", "restart", "status", "logs"):
        run([ROOT_DIR / "scripts/local.sh", subcmd, "-h"], stdout=subprocess.DEVNULL)
    for subcmd in (
        "check",
        "list",
        "list-models",
        "inspect",
        "inventory",
        "catalog-status",
        "status",
        "verify",
        "plan",
        "download",
        "info",
        "install-upload",
    ):
        run([ROOT_DIR / "scripts/models.sh", subcmd, "-h"], stdout=subprocess.DEVNULL)
    for subcmd in (
        "sync",
        "bootstrap",
        "start",
        "stop",
        "restart",
        "status",
        "logs",
        "models",
        "ready",
        "tunnel",
        "gpu",
    ):
        run([ROOT_DIR / "scripts/remote.sh", subcmd, "-h"], stdout=subprocess.DEVNULL)

    _help_contains(
        [ROOT_DIR / "scripts/models.sh", "-h"],
        ("inventory", "catalog-status", "status              兼容别名"),
        "models.sh top-level help drifted from model command contract",
    )
    _help_contains(
        [ROOT_DIR / "scripts/remote.sh", "models", "-h"],
        ("inventory", "catalog-status", "status 是 catalog-status 的兼容别名"),
        "remote.sh models help drifted from model command contract",
    )
