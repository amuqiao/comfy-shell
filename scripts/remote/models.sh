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

remote_models_upload_tmp_path() {
  local target_path="$1"
  local model_id="$2"
  local target_dir
  local target_base
  target_dir="$(dirname "$target_path")"
  target_base="$(basename "$target_path")"
  printf '%s/.%s.upload.%s.%s\n' "$target_dir" "$target_base" "$model_id" "$$"
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
        check|list|list-models|status|verify|plan|download|upload|logs)
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
      --model)
        case "$models_command" in
          status|verify|plan|download|upload|logs)
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
    status|verify) ;;
    plan|download)
      [[ -n "$models_bundle" || -n "$models_model" ]] || usage_error "models ${models_command} requires one bundle or --model MODEL_ID" usage_models
      ;;
    upload)
      [[ -z "$models_bundle" ]] || usage_error "models upload requires --model and takes no bundle" usage_models
      [[ -n "$models_model" ]] || usage_error "models upload requires --model MODEL_ID" usage_models
      [[ "$models_detach" == false ]] || usage_error "models upload does not support --detach" usage_models
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
  else
    remote_models_args=(./scripts/models.sh "$models_command")
    if [[ -n "$models_bundle" ]]; then
      remote_models_args+=("$models_bundle")
    fi
    if [[ -n "$models_model" ]]; then
      remote_models_args+=(--model "$models_model")
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
