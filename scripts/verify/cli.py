from __future__ import annotations

import shutil
import sys

from scripts.verify.common import VerifyContext, VerifyError, make_temp_dir
from scripts.verify.help import run_help
from scripts.verify.models_contract import run_config_and_models
from scripts.verify.read_only import run_read_only
from scripts.verify.syntax import run_diff_check, run_syntax


USAGE = """用法:
  ./scripts/verify.sh check
  ./scripts/verify.sh syntax
  ./scripts/verify.sh help-smoke
  ./scripts/verify.sh read-only
  ./scripts/verify.sh models
  ./scripts/verify.sh remote
  ./scripts/verify.sh diff
  ./scripts/verify.sh -h|--help

作用域:
  执行当前仓库 scripts/ 的最小可重复校验。用于修改脚本后的本地 smoke 验证。
  check 会验证 scripts 入口合同、只读 smoke、配置合同、模型合同、远程命令拼装合同和 diff 空白错误。

不负责:
  不启动 ComfyUI, 不连接真实远端, 不访问真实网络, 不下载真实大模型, 不安装依赖。

check 会执行:
  1. shell 入口语法检查
  2. 可用时执行 shellcheck
  3. Python helper 语法检查
  4. scripts 入口和子命令 help smoke
  5. 不联网、不启动服务的只读 smoke
  6. 默认 .env / 显式 --profile / 环境变量覆盖合同 smoke
  7. models catalog、status、download、upload 合同 smoke
  8. remote.sh 远程命令拼装、detach、logs、upload-file 合同 smoke
  9. git diff --check

输出:
  stdout 输出阶段标题和 check ok。
  stderr 输出参数错误、校验失败或下层工具诊断; 下载进度 smoke 的 PROGRESS 也在 stderr。

副作用与保护边界:
  只写临时目录和 /tmp 下 smoke 用模型目录; 不写真实模型目录。
  不启动进程, 不访问真实远端, 不访问真实网络。
  remote 相关检查只使用临时 ssh/rsync stub。

Exit Codes:
  0  成功。
  1  校验不通过或下层检查失败。
  2  参数、用法或前置条件错误。
  4  验证入口自身运行命令、临时文件或文件产物失败。
  其他非 0 由下层工具透传。
"""


def usage(stream=sys.stdout) -> None:
    print(USAGE, file=stream, end="")


def _new_context() -> VerifyContext:
    return VerifyContext(tmp_dir=make_temp_dir())


def _run_with_context(command: str) -> int:
    ctx = _new_context()
    try:
        if command == "check":
            run_syntax()
            run_help()
            run_read_only(ctx)
            run_config_and_models(ctx)
            from scripts.verify.remote_contract import run_remote_contract

            run_remote_contract(ctx)
            run_diff_check()
            print("check ok")
            return 0
        if command == "syntax":
            run_syntax()
            return 0
        if command == "help-smoke":
            run_help()
            return 0
        if command == "read-only":
            run_read_only(ctx)
            return 0
        if command == "models":
            run_config_and_models(ctx)
            return 0
        if command == "remote":
            run_config_and_models(ctx)
            from scripts.verify.remote_contract import run_remote_contract

            run_remote_contract(ctx)
            return 0
        if command == "diff":
            run_diff_check()
            return 0
        raise VerifyError(f"unknown command: {command}", 2)
    finally:
        shutil.rmtree(ctx.tmp_dir, ignore_errors=True)


def main(argv: list[str]) -> int:
    if not argv:
        usage()
        return 2
    if argv[0] in ("-h", "--help"):
        if len(argv) != 1:
            print("ERROR: -h|--help does not accept extra arguments", file=sys.stderr)
            usage(sys.stderr)
            return 2
        usage()
        return 0
    if len(argv) != 1:
        print(f"ERROR: unexpected argument: {argv[1]}", file=sys.stderr)
        usage(sys.stderr)
        return 2
    try:
        return _run_with_context(argv[0])
    except VerifyError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return exc.code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
