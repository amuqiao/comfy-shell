from __future__ import annotations

import subprocess

from scripts.verify.common import ROOT_DIR, section, run


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
