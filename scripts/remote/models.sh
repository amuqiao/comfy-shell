#!/usr/bin/env bash
# shellcheck disable=SC2154

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/remote/models.sh must be sourced, not executed directly\n' >&2
  exit 2
fi

remote_models_detach_cmd() {
  local dir="$1"
  local selector_kind="$2"
  local selector_value="$3"
  local selector_key="$selector_value"
  local remote_download_args
  if [[ "$selector_kind" == "model" ]]; then
    selector_key="model-${selector_value}"
    remote_download_args="$(quote_cmd ./scripts/models.sh download --model "$selector_value")"
  else
    remote_download_args="$(quote_cmd ./scripts/models.sh download "$selector_value")"
  fi
  local pid_file=".run/models-download-${selector_key}.pid"
  local log_file="logs/models-download-${selector_key}.log"
  # shellcheck disable=SC2016
  printf 'set -eu; cd %q; command -v nohup >/dev/null 2>&1 || { printf "ERROR: missing required command: nohup\\n" >&2; exit 2; }; mkdir -p .run logs; if [ -f %q ]; then pid=$(cat %q 2>/dev/null || true); if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then command=$(ps -ww -p "$pid" -o command= 2>/dev/null || ps -p "$pid" -o command= 2>/dev/null || true); case "$command" in *models-download*%q*) printf "RUNNING\\tmodels-download\\tpid=%%s log=%s\\n" "$pid"; exit 0 ;; *) rm -f %q ;; esac; fi; fi; rm -f %q; nohup sh -c '"'"'set -eu; pid_file=$1; shift; trap "rm -f \$pid_file" EXIT; "$@"'"'"' models-download %q %s > %q 2>&1 < /dev/null & pid=$!; printf "%%s\\n" "$pid" > %q; printf "STARTED\\tmodels-download\\tpid=%%s log=%s\\n" "$pid"\n' "$dir" "$pid_file" "$pid_file" "$selector_key" "$log_file" "$pid_file" "$pid_file" "$pid_file" "$remote_download_args" "$log_file" "$pid_file" "$log_file"
}

remote_models_logs_cmd() {
  local dir="$1"
  local selector_kind="$2"
  local selector_value="$3"
  local tail_lines="$4"
  local follow="$5"
  local selector_key="$selector_value"
  if [[ "$selector_kind" == "model" ]]; then
    selector_key="model-${selector_value}"
  fi
  local log_file="logs/models-download-${selector_key}.log"
  local log_command
  if [[ "$follow" == true ]]; then
    if [[ "$tail_lines" == "all" ]]; then
      log_command="$(quote_cmd tail -n +1 -F "$log_file")"
    else
      log_command="$(quote_cmd tail -n "$tail_lines" -F "$log_file")"
    fi
  elif [[ "$tail_lines" == "all" ]]; then
    log_command="$(quote_cmd cat "$log_file")"
  else
    log_command="$(quote_cmd tail -n "$tail_lines" "$log_file")"
  fi
  printf 'cd %q && if [ ! -f %q ]; then printf "ERROR: remote model log not found: %s\\n" >&2; exit 2; fi; %s\n' "$dir" "$log_file" "$log_file" "$log_command"
}

models_info_value() {
  local info="$1"
  local key="$2"
  awk -F '\t' -v key="$key" '$1 == key { print $2; found=1; exit } END { if (!found) exit 1 }' <<<"$info"
}

local_file_sha256() {
  python3 -c 'import hashlib, sys; h=hashlib.sha256(); f=open(sys.argv[1], "rb"); [h.update(chunk) for chunk in iter(lambda: f.read(1048576), b"")]; f.close(); print(h.hexdigest())' "$1"
}

remote_models_hash_function() {
  cat <<'EOF'
hash_file() {
  python3 -c 'import hashlib, sys; h=hashlib.sha256(); f=open(sys.argv[1], "rb"); [h.update(chunk) for chunk in iter(lambda: f.read(1048576), b"")]; f.close(); print(h.hexdigest())' "$1"
}
EOF
}

remote_models_path_function() {
  cat <<'EOF'
ensure_within_model_root() {
  python3 -c 'import pathlib, sys
root = pathlib.Path(sys.argv[1]).resolve(strict=False)
target = pathlib.Path(sys.argv[2]).resolve(strict=False)
try:
    target.relative_to(root)
except ValueError:
    print(f"ERROR: upload path escapes COMFY_MODEL_ROOT: {target}", file=sys.stderr)
    sys.exit(4)
' "$1" "$2"
}
EOF
}

remote_models_config_function() {
  cat <<'EOF'
remote_config_value() {
  if [ -n "${COMFY_MODEL_ROOT:-}" ]; then
    printf '%s\n' "$COMFY_MODEL_ROOT"
    return
  fi
  [ -f .env ] || return 0
  awk -v key="COMFY_MODEL_ROOT" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      line=$0
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)
      pattern="^[[:space:]]*" key "[[:space:]]*="
      if (line ~ pattern) {
        sub(/^[^=]*=/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
          line=substr(line, 2, length(line) - 2)
        }
        value=line
      }
    }
    END { if (value != "") print value }
  ' .env
}
EOF
}

remote_models_upload_tmp_path() {
  local target_path="$1"
  local model_id="$2"
  local target_dir
  local target_base
  target_dir="$(dirname "$target_path")"
  target_base="$(basename "$target_path")"
  printf '%s/.%s.upload.%s.%s\n' "$target_dir" "$target_base" "$model_id" "$$"
}

remote_models_upload_file_prepare_cmd() {
  local dir="$1"
  local model_dir="$2"
  local filename="$3"
  local expected_sha="$4"
  local expected_size="$5"
  local hash_function
  local path_function
  local config_function
  hash_function="$(remote_models_hash_function)"
  path_function="$(remote_models_path_function)"
  config_function="$(remote_models_config_function)"
  # shellcheck disable=SC2016
  printf 'set -eu; cd %q; action=models-upload-file-prepare; command -v python3 >/dev/null 2>&1 || { printf "ERROR: missing required command: python3\n" >&2; exit 2; }; %s\n%s\n%s\nmodel_dir=%q; filename=%q; expected_sha=%q; expected_size=%q; model_root="$(remote_config_value)"; if [ -z "$model_root" ]; then printf "ERROR: COMFY_MODEL_ROOT is required in remote .env or environment\n" >&2; exit 2; fi; case "$model_root" in /*) ;; *) model_root="$PWD/$model_root" ;; esac; target_dir="${model_root%%%%/}/$model_dir"; target_path="$target_dir/$filename"; tmp_path="$target_dir/.$filename.upload-file.$$"; ensure_within_model_root "$model_root" "$target_path"; ensure_within_model_root "$model_root" "$tmp_path"; mkdir -p "$target_dir"; ensure_within_model_root "$model_root" "$target_path"; ensure_within_model_root "$model_root" "$tmp_path"; if [ -e "$target_path" ]; then actual_size=$(wc -c <"$target_path" | tr -d " "); actual_sha=$(hash_file "$target_path"); if [ "$actual_size" = "$expected_size" ] && [ "$actual_sha" = "$expected_sha" ]; then printf "SKIPPED\tmodels-upload-file\tremote target already identical: %%s\n" "$target_path"; exit 0; fi; printf "ERROR: remote target exists with different content: %%s\n" "$target_path" >&2; exit 4; fi; rm -f "$tmp_path"; printf "ROOT\t%%s\n" "$model_root"; printf "TARGET\t%%s\n" "$target_path"; printf "TMP\t%%s\n" "$tmp_path"\n' "$dir" "$hash_function" "$path_function" "$config_function" "$model_dir" "$filename" "$expected_sha" "$expected_size"
}

remote_models_upload_file_install_cmd() {
  local dir="$1"
  local model_root="$2"
  local target_path="$3"
  local tmp_path="$4"
  local expected_sha="$5"
  local expected_size="$6"
  local hash_function
  local path_function
  hash_function="$(remote_models_hash_function)"
  path_function="$(remote_models_path_function)"
  # shellcheck disable=SC2016
  printf 'set -eu; cd %q; action=models-upload-file-install; command -v python3 >/dev/null 2>&1 || { printf "ERROR: missing required command: python3\n" >&2; exit 2; }; %s\n%s\nmodel_root=%q; target_path=%q; tmp_path=%q; expected_sha=%q; expected_size=%q; ensure_within_model_root "$model_root" "$target_path"; ensure_within_model_root "$model_root" "$tmp_path"; trap '"'"'rm -f "$tmp_path"'"'"' EXIT; if [ ! -f "$tmp_path" ]; then printf "ERROR: upload temp file missing: %%s\n" "$tmp_path" >&2; exit 4; fi; actual_size=$(wc -c <"$tmp_path" | tr -d " "); if [ "$actual_size" != "$expected_size" ]; then printf "ERROR: upload temp size mismatch: %%s != %%s\n" "$actual_size" "$expected_size" >&2; exit 4; fi; actual_sha=$(hash_file "$tmp_path"); if [ "$actual_sha" != "$expected_sha" ]; then printf "ERROR: upload temp sha256 mismatch: %%s\n" "$actual_sha" >&2; exit 4; fi; if [ -e "$target_path" ]; then target_size=$(wc -c <"$target_path" | tr -d " "); target_sha=$(hash_file "$target_path"); if [ "$target_size" = "$expected_size" ] && [ "$target_sha" = "$expected_sha" ]; then printf "SKIPPED\tmodels-upload-file\tremote target already identical: %%s\n" "$target_path"; rm -f "$tmp_path"; trap - EXIT; exit 0; fi; printf "ERROR: remote target exists with different content: %%s\n" "$target_path" >&2; exit 4; fi; mkdir -p "$(dirname "$target_path")"; ensure_within_model_root "$model_root" "$target_path"; ensure_within_model_root "$model_root" "$tmp_path"; mv "$tmp_path" "$target_path"; trap - EXIT; printf "SUCCESS\tmodels-upload-file\t%%s\n" "$target_path"\n' "$dir" "$hash_function" "$path_function" "$model_root" "$target_path" "$tmp_path" "$expected_sha" "$expected_size"
}

remote_models_upload_preflight_cmd() {
  local dir="$1"
  local model_id="$2"
  local target_path="$3"
  local tmp_path="$4"
  local target_dir
  target_dir="$(dirname "$target_path")"
  # shellcheck disable=SC2016
  printf 'set -eu; cd %q; mkdir -p %q; if [ -e %q ]; then if ./scripts/models.sh verify --model %q >/dev/null; then printf "SKIPPED\\tmodels-upload\\tremote target already verified: %s\\n"; exit 0; fi; printf "ERROR: remote target exists but does not verify: %s\\n" >&2; exit 4; fi; rm -f %q\n' "$dir" "$target_dir" "$target_path" "$model_id" "$target_path" "$target_path" "$tmp_path"
}

remote_models_upload_install_cmd() {
  local dir="$1"
  local model_id="$2"
  local tmp_path="$3"
  # shellcheck disable=SC2016
  printf 'set -eu; cd %q; tmp_path=%q; trap '"'"'rm -f "$tmp_path"'"'"' EXIT; ./scripts/models.sh install-upload --model %q --file "$tmp_path"; trap - EXIT\n' "$dir" "$tmp_path" "$model_id"
}

handle_remote_models() {
  host=""
  remote_dir=""
  profile=""
  models_command=""
  models_bundle=""
  models_model=""
  models_file=""
  models_to=""
  models_name=""
  models_all=false
  models_detach=false
  models_tail=""
  models_follow=false
  while [[ $# -gt 0 ]]; do
    if [[ -z "$models_command" ]]; then
      if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
      case "$1" in
        -h|--help)
          usage_models
          exit 0
          ;;
        check|list|list-models|inventory|catalog-status|status|verify|plan|download|upload|upload-file|logs)
          models_command="$1"
          shift
          ;;
        inspect)
          usage_error "remote models does not support inspect; run ./scripts/models.sh inspect locally" usage_models
          ;;
        -*)
          usage_error "models requires a models subcommand before models args" usage_models
          ;;
        *)
          usage_error "unsupported remote models subcommand: $1" usage_models
          ;;
      esac
      continue
    fi

    case "$1" in
      -h|--help)
        usage_error "remote models does not proxy remote models.sh help; run ./scripts/models.sh ${models_command} -h on the target checkout" usage_models
        ;;
      --profile|--host|--dir)
        usage_error "$1 must appear before the models subcommand and is only used by local remote.sh" usage_models
        ;;
      --detach)
        [[ "$models_command" == "download" ]] || usage_error "--detach is only supported for models download" usage_models
        models_detach=true
        shift
        ;;
      --all)
        [[ "$models_command" == "inventory" ]] || usage_error "--all is only supported for models inventory" usage_models
        models_all=true
        shift
        ;;
      --model)
        case "$models_command" in
          catalog-status|status|verify|plan|download|upload|logs)
            [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--model requires a model id" usage_models
            [[ -z "$models_model" ]] || usage_error "remote models accepts at most one --model" usage_models
            models_model="$2"
            shift 2
            ;;
          *)
            usage_error "--model is not supported for models ${models_command}" usage_models
            ;;
        esac
        ;;
      --file)
        [[ "$models_command" == "upload-file" ]] || usage_error "--file is only supported for models upload-file" usage_models
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--file requires a file path" usage_models
        models_file="$2"
        shift 2
        ;;
      --to)
        [[ "$models_command" == "upload-file" ]] || usage_error "--to is only supported for models upload-file" usage_models
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--to requires a model directory" usage_models
        models_to="$2"
        shift 2
        ;;
      --name)
        [[ "$models_command" == "upload-file" ]] || usage_error "--name is only supported for models upload-file" usage_models
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--name requires a filename" usage_models
        models_name="$2"
        shift 2
        ;;
      --tail)
        [[ "$models_command" == "logs" ]] || usage_error "--tail is only supported for models logs" usage_models
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--tail requires a value" usage_models
        models_tail="$2"
        shift 2
        ;;
      --follow)
        [[ "$models_command" == "logs" ]] || usage_error "--follow is only supported for models logs" usage_models
        models_follow=true
        shift
        ;;
      -*)
        usage_error "remote models does not forward models.sh options: $1" usage_models
        ;;
      *)
        [[ -z "$models_bundle" ]] || usage_error "remote models accepts at most one bundle argument" usage_models
        [[ -z "$models_model" ]] || usage_error "remote models accepts either a bundle argument or --model, not both" usage_models
        models_bundle="$1"
        shift
        ;;
    esac
  done
  [[ -n "$models_command" ]] || usage_error "models requires a models subcommand" usage_models
  if [[ -n "$models_bundle" ]]; then
    validate_model_bundle "$models_bundle"
  fi
  if [[ -n "$models_model" ]]; then
    validate_model_id "$models_model"
  fi
  case "$models_command" in
    list)
      [[ -z "$models_bundle" ]] || usage_error "models list takes no bundle argument" usage_models
      [[ -z "$models_model" ]] || usage_error "models list does not support --model" usage_models
      ;;
    list-models)
      [[ -z "$models_model" ]] || usage_error "models list-models does not support --model" usage_models
      ;;
    check)
      [[ -z "$models_bundle" ]] || usage_error "models check takes no bundle argument" usage_models
      [[ -z "$models_model" ]] || usage_error "models check does not support --model" usage_models
      ;;
    inventory)
      [[ -z "$models_bundle" ]] || usage_error "models inventory takes no bundle argument" usage_models
      [[ -z "$models_model" ]] || usage_error "models inventory does not support --model" usage_models
      ;;
    catalog-status|status|verify) ;;
    plan|download)
      [[ -n "$models_bundle" || -n "$models_model" ]] || usage_error "models ${models_command} requires one bundle or --model MODEL_ID" usage_models
      ;;
    upload)
      [[ -z "$models_bundle" ]] || usage_error "models upload requires --model and takes no bundle" usage_models
      [[ -n "$models_model" ]] || usage_error "models upload requires --model MODEL_ID" usage_models
      [[ "$models_detach" == false ]] || usage_error "models upload does not support --detach" usage_models
      ;;
    upload-file)
      [[ -z "$models_bundle" ]] || usage_error "models upload-file takes no bundle argument" usage_models
      [[ -z "$models_model" ]] || usage_error "models upload-file does not support --model" usage_models
      [[ "$models_detach" == false ]] || usage_error "models upload-file does not support --detach" usage_models
      [[ -n "$models_file" ]] || usage_error "models upload-file requires --file FILE" usage_models
      [[ -n "$models_to" ]] || usage_error "models upload-file requires --to MODEL_DIR" usage_models
      validate_model_upload_dir "$models_to"
      models_file="$(abs_path "$models_file")"
      [[ -f "$models_file" ]] || die "local upload file not found: $models_file" 2
      [[ -s "$models_file" ]] || die "local upload file is empty: $models_file" 2
      if [[ -z "$models_name" ]]; then
        models_name="$(basename "$models_file")"
      fi
      validate_model_upload_name "$models_name"
      ;;
    logs)
      [[ -n "$models_bundle" || -n "$models_model" ]] || usage_error "models logs requires one bundle or --model MODEL_ID" usage_models
      models_tail="${models_tail:-$(config_value REMOTE_LOG_TAIL)}"
      models_tail="${models_tail:-$DEFAULT_LOG_TAIL}"
      validate_tail "$models_tail"
      ;;
  esac
  require_host_dir
  require_cmd ssh
  if [[ "$models_command" == "logs" ]]; then
    if [[ -n "$models_model" ]]; then
      remote_command="$(remote_models_logs_cmd "$remote_dir" model "$models_model" "$models_tail" "$models_follow")"
    else
      remote_command="$(remote_models_logs_cmd "$remote_dir" bundle "$models_bundle" "$models_tail" "$models_follow")"
    fi
    print_remote_plan \
      "models logs" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "" \
      "$remote_command"
  elif [[ "$models_command" == "download" && "$models_detach" == true ]]; then
    if [[ -n "$models_model" ]]; then
      remote_command="$(remote_models_detach_cmd "$remote_dir" model "$models_model")"
    else
      remote_command="$(remote_models_detach_cmd "$remote_dir" bundle "$models_bundle")"
    fi
    print_remote_plan \
      "models download --detach" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "" \
      "$remote_command"
  elif [[ "$models_command" == "upload" ]]; then
    require_cmd rsync
    local_info="$("$ROOT_DIR/scripts/models.sh" info --model "$models_model")"
    local_path="$(models_info_value "$local_info" path)" || die "unable to resolve local model path for $models_model" 2
    local_sha="$(models_info_value "$local_info" sha256)" || die "unable to resolve local model sha256 for $models_model" 2
    [[ -n "$local_sha" ]] || die "model $models_model has no sha256; upload is disabled for reliability" 2
    "$ROOT_DIR/scripts/models.sh" verify --model "$models_model" >/dev/null

    remote_info_command="$(remote_cd_cmd "$remote_dir" ./scripts/models.sh info --model "$models_model")"
    remote_info="$(ssh -o ConnectTimeout=10 "$host" "$remote_info_command")"
    remote_path="$(models_info_value "$remote_info" path)" || die "unable to resolve remote model path for $models_model" 2
    remote_sha="$(models_info_value "$remote_info" sha256)" || die "unable to resolve remote model sha256 for $models_model" 2
    [[ "$local_sha" == "$remote_sha" ]] || die "local and remote catalog sha256 differ for $models_model" 2
    remote_tmp_path="$(remote_models_upload_tmp_path "$remote_path" "$models_model")"
    preflight_command="$(remote_models_upload_preflight_cmd "$remote_dir" "$models_model" "$remote_path" "$remote_tmp_path")"
    preflight_output="$(ssh -o ConnectTimeout=10 "$host" "$preflight_command")"
    if [[ "$preflight_output" == SKIPPED$'\t'* ]]; then
      print_remote_plan \
        "models upload" \
        "$host" \
        "$remote_dir" \
        "$profile" \
        "" \
        "$preflight_command"
      printf '%s\n' "$preflight_output"
      exit 0
    fi
    install_command="$(remote_models_upload_install_cmd "$remote_dir" "$models_model" "$remote_tmp_path")"
    print_remote_plan \
      "models upload" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "" \
      "$preflight_command" \
      "rsync $local_path -> ${host}:${remote_tmp_path}" \
      "$install_command"
    rsync_args=(-avh --progress --rsh "ssh -o ConnectTimeout=10" "$local_path" "${host}:$remote_tmp_path")
    print_command rsync "${rsync_args[@]}"
    rsync "${rsync_args[@]}"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$install_command")
    exec "${ssh_args[@]}"
  elif [[ "$models_command" == "upload-file" ]]; then
    require_cmd rsync
    require_cmd python3
    local_size="$(wc -c <"$models_file" | tr -d ' ')"
    local_sha="$(local_file_sha256 "$models_file")"
    preflight_command="$(remote_models_upload_file_prepare_cmd "$remote_dir" "$models_to" "$models_name" "$local_sha" "$local_size")"
    preflight_output="$(ssh -o ConnectTimeout=10 "$host" "$preflight_command")"
    if [[ "$preflight_output" == SKIPPED$'\t'* ]]; then
      print_remote_plan \
        "models upload-file" \
        "$host" \
        "$remote_dir" \
        "$profile" \
        "" \
        "$preflight_command"
      printf '%s\n' "$preflight_output"
      exit 0
    fi
    remote_model_root="$(models_info_value "$preflight_output" ROOT)" || die "unable to resolve remote upload-file model root" 2
    remote_path="$(models_info_value "$preflight_output" TARGET)" || die "unable to resolve remote upload-file target path" 2
    remote_tmp_path="$(models_info_value "$preflight_output" TMP)" || die "unable to resolve remote upload-file temp path" 2
    install_command="$(remote_models_upload_file_install_cmd "$remote_dir" "$remote_model_root" "$remote_path" "$remote_tmp_path" "$local_sha" "$local_size")"
    print_remote_plan \
      "models upload-file" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "" \
      "$preflight_command" \
      "rsync $models_file -> ${host}:${remote_tmp_path}" \
      "$install_command"
    rsync_args=(-avh --progress --rsh "ssh -o ConnectTimeout=10" "$models_file" "${host}:$remote_tmp_path")
    print_command rsync "${rsync_args[@]}"
    rsync "${rsync_args[@]}"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$install_command")
    exec "${ssh_args[@]}"
  else
    remote_models_args=(./scripts/models.sh "$models_command")
    if [[ -n "$models_bundle" ]]; then
      remote_models_args+=("$models_bundle")
    fi
    if [[ -n "$models_model" ]]; then
      remote_models_args+=(--model "$models_model")
    fi
    if [[ "$models_all" == true ]]; then
      remote_models_args+=(--all)
    fi
    print_remote_plan \
      "models ${models_command}" \
      "$host" \
      "$remote_dir" \
      "$profile" \
      "" \
      "cd $remote_dir && $(quote_cmd "${remote_models_args[@]}")"
    remote_command="$(remote_cd_cmd "$remote_dir" "${remote_models_args[@]}")"
  fi
  ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
  exec "${ssh_args[@]}"
}
