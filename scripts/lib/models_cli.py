#!/usr/bin/env python3
"""Compatibility wrapper for scripts/models.sh.

The implementation lives in scripts.models.* modules. Keep this path importable
for older local tooling that still executes scripts/lib/models_cli.py directly.
"""

from __future__ import annotations

import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from scripts.models.cli import main  # noqa: E402
from scripts.models.common import CliError  # noqa: E402


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BrokenPipeError:
        raise SystemExit(0)
    except CliError as exc:
        sys.stdout.flush()
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(exc.code)
