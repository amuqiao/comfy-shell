#!/usr/bin/env bash
# shellcheck disable=SC2034

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/remote/core.sh must be sourced, not executed directly\n' >&2
  exit 2
fi

# shellcheck disable=SC2034
DEFAULT_READY_URL="http://127.0.0.1:8188"
# shellcheck disable=SC2034
DEFAULT_LOCAL_PORT="8188"
# shellcheck disable=SC2034
DEFAULT_REMOTE_HOST="127.0.0.1"
# shellcheck disable=SC2034
DEFAULT_REMOTE_PORT="8188"
# shellcheck disable=SC2034
DEFAULT_LOG_TAIL="200"
# shellcheck disable=SC2034
DEFAULT_CONNECT_TIMEOUT="10"

validate_remote_host() {
  local value="$1"
  [[ "$value" == *@* ]] || usage_error "--host must use USER@HOST" usage
  [[ "$value" != -* && "$value" != *[[:space:]]* ]] || usage_error "--host contains invalid characters: $value" usage
}

validate_remote_dir() {
  local value="$1"
  [[ "$value" == /* ]] || usage_error "--dir must be an absolute path" usage
  [[ "$value" =~ ^/[A-Za-z0-9._/+:-]*[A-Za-z0-9._/+:-]$ ]] || usage_error "--dir contains invalid characters: $value" usage
  [[ "$value" != *:* ]] || usage_error "--dir must not contain colon characters" usage
  [[ "$value" != *"/../"* && "$value" != */.. && "$value" != *"/./"* && "$value" != */. ]] || usage_error "--dir must not contain . or .. path segments" usage
}

validate_simple_host() {
  local label="$1"
  local value="$2"
  [[ "$value" != -* && "$value" != *[[:space:]]* ]] || usage_error "$label contains invalid characters: $value" usage
}

validate_port() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 && "$value" -le 65535 ]] || usage_error "$label must be a port between 1 and 65535" usage
}

validate_tail() {
  local value="$1"
  [[ "$value" == "all" || "$value" =~ ^[0-9]+$ ]] || usage_error "--tail must be a non-negative integer or all" usage
}

validate_positive_uint() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 ]] || usage_error "$label must be a positive integer" usage
}

validate_model_bundle() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || usage_error "model bundle contains invalid characters: $value" usage_models
}

validate_model_id() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || usage_error "model id contains invalid characters: $value" usage_models
}

validate_profile_arg() {
  local value="$1"
  [[ "$value" != -* && "$value" != *[[:space:]]* ]] || usage_error "--profile contains invalid characters: $value" usage
  [[ "$value" =~ ^[A-Za-z0-9._/+:-]+$ ]] || usage_error "--profile contains invalid characters: $value" usage
  [[ "$value" != *:* ]] || usage_error "--profile must not contain colon characters" usage
  [[ "$value" != *"/../"* && "$value" != ../* && "$value" != */.. && "$value" != ".." ]] || usage_error "--profile must not contain .. path segments" usage
}

validate_url() {
  local value="$1"
  [[ "$value" =~ ^https?://[^[:space:]]+$ ]] || usage_error "--url must be an http(s) URL without whitespace" usage
}

quote_cmd() {
  local out=""
  local part
  for part in "$@"; do
    if [[ -n "$out" ]]; then
      out+=" "
    fi
    out+="$(printf '%q' "$part")"
  done
  printf '%s\n' "$out"
}

remote_cd_cmd() {
  local dir="$1"
  shift
  printf 'cd %q && %s\n' "$dir" "$(quote_cmd "$@")"
}

remote_ready_cmd() {
  local endpoint="${1%/}/system_stats"
  # shellcheck disable=SC2016
  printf 'command -v curl >/dev/null 2>&1 || { printf "ERROR: missing required command: curl\\n" >&2; exit 2; }; code=$(curl --connect-timeout 2 --max-time 5 -sS -o /dev/null -w "%%{http_code}" %q); curl_status=$?; if [ "$curl_status" -ne 0 ]; then case "$curl_status" in 7|28|52) printf "000\\n"; exit 1 ;; *) printf "ERROR: curl failed with exit %%s\\n" "$curl_status" >&2; exit 4 ;; esac; fi; printf "%%s\\n" "$code"; [ "$code" = 200 ]\n' "$endpoint"
}

remote_gpu_snapshot_cmd() {
  printf '%s' "command -v nvidia-smi >/dev/null 2>&1 || { printf 'ERROR: missing required command: nvidia-smi\n' >&2; exit 2; }; printf '%s\n' __REMOTE_GPU_SUMMARY__; nvidia-smi --query-gpu=index,uuid,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,power.limit,compute_mode,driver_version --format=csv,noheader,nounits; printf '%s\n' __REMOTE_GPU_PROCESSES__; nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits"
}

require_yes() {
  local confirmed="$1"
  [[ "$confirmed" == true ]] || usage_error "remote write/lifecycle command requires --yes" usage
}

remote_config_error() {
  local missing="$1"
  local needs_dir="$2"
  local verb="is"
  if [[ "$missing" == *,* ]]; then
    verb="are"
  fi

  {
    printf 'ERROR: %s %s not configured.\n\n' "$missing" "$verb"
    printf 'remote.sh does not guess remote targets. Configure real values through exported environment, --profile FILE, or %s.\n\n' "$CONFIG_FILE"
    printf 'Add to config:\n'
    printf '  REMOTE_HOST=wangqiao@47.94.108.140\n'
    if [[ "$needs_dir" == true ]]; then
      printf '  REMOTE_DIR=/data/wangqiao/comfy-shell\n'
    else
      printf '  # REMOTE_DIR=/data/wangqiao/comfy-shell  # needed by checkout commands\n'
    fi
    printf '\nThen rerun the same command.\n'
    printf '\nOne-off override examples:\n'
    if [[ "$needs_dir" == true ]]; then
      printf '  ./scripts/remote.sh status --host wangqiao@47.94.108.140 --dir /data/wangqiao/comfy-shell\n'
    else
      printf '  ./scripts/remote.sh tunnel --host wangqiao@47.94.108.140\n'
    fi
  } >&2
  exit 2
}

apply_remote_host_default() {
  if [[ -z "${host:-}" ]]; then
    host="$(config_value REMOTE_HOST)"
  fi
}

apply_remote_dir_default() {
  if [[ -z "${remote_dir:-}" ]]; then
    remote_dir="$(config_value REMOTE_DIR)"
  fi
}

require_host() {
  apply_remote_host_default
  [[ -n "$host" ]] || remote_config_error "REMOTE_HOST" false
  validate_remote_host "$host"
}

require_host_dir() {
  local missing=""
  apply_remote_host_default
  apply_remote_dir_default
  if [[ -z "$host" ]]; then
    missing="REMOTE_HOST"
  fi
  if [[ -z "$remote_dir" ]]; then
    missing="${missing:+$missing, }REMOTE_DIR"
  fi
  [[ -z "$missing" ]] || remote_config_error "$missing" true
  validate_remote_host "$host"
  validate_remote_dir "$remote_dir"
}

print_remote_plan() {
  local action="$1"
  local host_value="$2"
  local dir_value="$3"
  local config_value="$4"
  local delete_value="$5"
  shift 5
  local remote_action

  section "Remote Plan"
  event "ACTION" "$action"
  event "HOST" "$host_value"
  if [[ -n "$dir_value" ]]; then
    event "DIR" "$dir_value"
  fi
  if [[ -n "$config_value" ]]; then
    event "CONFIG" "$config_value"
  fi
  if [[ -n "$delete_value" ]]; then
    event "DELETE" "$delete_value"
  fi
  for remote_action in "$@"; do
    event "REMOTE" "$remote_action"
  done
}

parse_host_common() {
  consumed=0
  case "$1" in
    --profile)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--profile requires a value" usage
      validate_profile_arg "$2"
      # shellcheck disable=SC2034
      profile="$2"
      set_config_file "$2"
      require_config_file
      consumed=2
      return 0
      ;;
    --host)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--host requires a value" usage
      host="$2"
      consumed=2
      return 0
      ;;
  esac
  return 1
}

parse_host_dir_common() {
  if parse_host_common "$@"; then
    return 0
  fi
  consumed=0
  case "$1" in
    --dir)
      [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--dir requires a value" usage
      remote_dir="$2"
      # shellcheck disable=SC2034
      consumed=2
      return 0
      ;;
  esac
  return 1
}
