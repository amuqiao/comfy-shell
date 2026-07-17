from __future__ import annotations

import hashlib
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


ROOT_DIR = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = ROOT_DIR / "scripts"
TOOLS_DIR = ROOT_DIR / "tools"


class VerifyError(Exception):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


@dataclass
class VerifyContext:
    tmp_dir: Path
    contract_profile: Path | None = None
    civitai_catalog: Path | None = None
    civitai_payload_file: Path | None = None
    civitai_sha: str = ""
    civitai_size: str = ""


def die(message: str, code: int = 1) -> None:
    raise VerifyError(message, code)


def section(name: str) -> None:
    print(f"\n===== {name} =====")


def event(kind: str, name: str, detail: str = "") -> None:
    print(f"{kind:<10} {name:<18} {detail}")


def command_label(argv: list[str | Path]) -> str:
    return " ".join(shlex.quote(str(part)) for part in argv)


def merged_env(extra: Mapping[str, str | Path] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    if extra:
        env.update({key: str(value) for key, value in extra.items()})
    return env


def run(
    argv: list[str | Path],
    *,
    env: Mapping[str, str | Path] | None = None,
    stdout=None,
    stderr=None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            [str(part) for part in argv],
            cwd=ROOT_DIR,
            env=merged_env(env),
            text=True,
            stdout=stdout,
            stderr=stderr,
            check=False,
        )
    except OSError as exc:
        die(f"unable to run command: {command_label(argv)}: {exc}", 4)
    if check and result.returncode != 0:
        die(f"command failed ({result.returncode}): {command_label(argv)}", result.returncode)
    return result


def capture(
    argv: list[str | Path],
    *,
    env: Mapping[str, str | Path] | None = None,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    return run(argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def expect_status(expected: int, argv: list[str | Path], *, env: Mapping[str, str | Path] | None = None) -> None:
    result = run(argv, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if result.returncode != expected:
        die(f"expected exit {expected}, got {result.returncode}: {command_label(argv)}", 1)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def chmod_x(path: Path) -> None:
    path.chmod(path.stat().st_mode | 0o111)


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_size(path: Path) -> str:
    return str(path.stat().st_size)


def abs_path(path: Path) -> Path:
    return path.resolve(strict=False)


def make_temp_dir() -> Path:
    return Path(tempfile.mkdtemp(prefix="comfy-shell-verify."))


def require_file(value: Path | None, label: str) -> Path:
    if value is None:
        die(f"internal verify context missing: {label}", 1)
    return value


def env_value_from(key: str, file_path: Path) -> str:
    if not file_path.is_file():
        return ""
    value = ""
    for raw_line in file_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].lstrip()
        if not line.startswith(f"{key}") or "=" not in line:
            continue
        lhs, rhs = line.split("=", 1)
        if lhs.strip() != key:
            continue
        parsed = rhs.split(" #", 1)[0].strip()
        if (parsed.startswith('"') and parsed.endswith('"')) or (
            parsed.startswith("'") and parsed.endswith("'")
        ):
            parsed = parsed[1:-1]
        if parsed:
            value = parsed
    return value


def shell_script_result(script: str, args: list[str | Path] | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["bash", "-c", script, "_", *(str(arg) for arg in (args or []))],
            cwd=ROOT_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        die(f"unable to run command: bash -c <script>: {exc}", 4)


def remote_model_helper_output(function_name: str, args: list[str | Path]) -> str:
    script = f"""
set -euo pipefail
source {shlex.quote(str(SCRIPTS_DIR / "lib/common.sh"))}
source {shlex.quote(str(SCRIPTS_DIR / "remote/core.sh"))}
source {shlex.quote(str(SCRIPTS_DIR / "remote/models.sh"))}
{function_name} "$@"
"""
    result = shell_script_result(script, args)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        die(f"remote helper {function_name} failed", result.returncode)
    return result.stdout


def shellcheck_available() -> bool:
    return shutil.which("shellcheck") is not None
