from __future__ import annotations

import sys

from scripts.models.catalog import check_catalog, list_bundles, list_models
from scripts.models.common import CliError, die, parse_model_args, section
from scripts.models.download import download_bundle, download_model, install_upload
from scripts.models.plan import print_model_info, print_plan
from scripts.models.status import print_status
from scripts.models.workflow import inspect_workflow


def main(argv: list[str]) -> int:
    if not argv:
        return 2

    command = argv[0]
    args = argv[1:]

    if command == "list":
        if args:
            die("list takes no arguments", 2)
        section("Model Bundles")
        return list_bundles()

    if command == "list-models":
        if len(args) > 1:
            die("list-models takes zero or one bundle", 2)
        section("Model Catalog Models")
        return list_models(args[0] if args else "")

    if command == "check":
        if args:
            die("check takes no arguments", 2)
        section("Model Catalog Check")
        return check_catalog()

    if command == "inspect":
        if len(args) != 1:
            die("inspect requires one workflow file", 2)
        section("Workflow Models")
        return inspect_workflow(args[0])

    if command in {"status", "verify"}:
        parsed_args, config_file, model_id, upload_file = parse_model_args(command, args)
        if upload_file:
            die(f"{command} does not accept --file", 2)
        if len(parsed_args) > 1:
            die(f"{command} takes zero or one bundle", 2)
        section("Model Status" if command == "status" else "Model Verify")
        return print_status(command, parsed_args[0] if parsed_args else "", model_id, config_file)

    if command == "plan":
        parsed_args, config_file, model_id, upload_file = parse_model_args(command, args)
        if upload_file:
            die("plan does not accept --file", 2)
        if not model_id and len(parsed_args) != 1:
            die("plan requires one bundle", 2)
        if model_id and parsed_args:
            die("plan accepts either one bundle or --model, not both", 2)
        section("Model Plan")
        return print_plan(parsed_args[0] if parsed_args else "", model_id, config_file)

    if command == "download":
        parsed_args, config_file, model_id, upload_file = parse_model_args(command, args)
        if upload_file:
            die("download does not accept --file", 2)
        if not model_id and len(parsed_args) != 1:
            die("download requires one bundle", 2)
        if model_id and parsed_args:
            die("download accepts either one bundle or --model, not both", 2)
        if model_id:
            return download_model(model_id, config_file)
        return download_bundle(parsed_args[0], config_file)

    if command == "info":
        parsed_args, config_file, model_id, upload_file = parse_model_args(command, args)
        if parsed_args:
            die("info requires --model and takes no bundle", 2)
        if upload_file:
            die("info does not accept --file", 2)
        if not model_id:
            die("info requires --model", 2)
        return print_model_info(model_id, config_file)

    if command == "install-upload":
        parsed_args, config_file, model_id, upload_file = parse_model_args(command, args)
        if parsed_args:
            die("install-upload requires --model and --file, and takes no bundle", 2)
        if not model_id:
            die("install-upload requires --model", 2)
        if not upload_file:
            die("install-upload requires --file", 2)
        return install_upload(model_id, upload_file, config_file)

    die(f"unknown command: {command}", 2)
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BrokenPipeError:
        raise SystemExit(0)
    except CliError as exc:
        sys.stdout.flush()
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(exc.code)
