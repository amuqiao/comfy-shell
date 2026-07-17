from __future__ import annotations

import os
import subprocess
import sys

from scripts.verify.common import ROOT_DIR, SCRIPTS_DIR, TOOLS_DIR, event, run, section, shellcheck_available


def run_syntax() -> None:
    section("Shell Syntax")
    shell_files = (
        sorted(SCRIPTS_DIR.glob("*.sh"))
        + sorted((SCRIPTS_DIR / "lib").glob("*.sh"))
        + sorted((SCRIPTS_DIR / "remote").glob("*.sh"))
        + sorted(TOOLS_DIR.glob("*.sh"))
    )
    run(["bash", "-n", *shell_files])

    section("Shellcheck")
    if shellcheck_available():
        run(["shellcheck", *shell_files])
    else:
        event("SKIP", "shellcheck", "not found")

    section("Python Syntax")
    python_files = (
        sorted((SCRIPTS_DIR / "models").glob("*.py"))
        + sorted((SCRIPTS_DIR / "verify").glob("*.py"))
        + [
            SCRIPTS_DIR / "lib/models_cli.py",
            SCRIPTS_DIR / "lib/remote_gpu_format.py",
        ]
    )
    env = os.environ.copy()
    env["PYTHONPYCACHEPREFIX"] = f"{os.environ.get('TMPDIR', '/tmp')}/comfy-shell-pycache"
    run([sys.executable, "-m", "py_compile", *python_files], env=env)


def run_diff_check() -> None:
    section("Diff Check")
    run(["git", "-C", ROOT_DIR, "diff", "--check"])
