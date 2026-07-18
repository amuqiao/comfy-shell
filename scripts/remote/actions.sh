#!/usr/bin/env bash
# shellcheck disable=SC2154

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/remote/actions.sh must be sourced, not executed directly\n' >&2
  exit 2
fi

handle_remote_sync() {
  host=""
  remote_dir=""
  profile=""
  local_dir="$ROOT_DIR"
  follow_links=false
  delete_remote=false
  yes=false
  while [[ $# -gt 0 ]]; do
    if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      --local-dir)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--local-dir requires a value" usage
        local_dir="$2"
        shift 2
        ;;
      --follow-links)
        follow_links=true
        shift
        ;;
      --delete)
        delete_remote=true
        shift
        ;;
      --yes)
        yes=true
        shift
        ;;
      -h|--help)
        usage_sync
        exit 0
        ;;
      *)
        usage_error "unknown sync option: $1" usage_sync
        ;;
    esac
  done
  require_host_dir
  require_yes "$yes"
  require_cmd ssh
  require_cmd rsync
  local_dir="$(abs_path "$local_dir")"
  [[ -d "$local_dir" ]] || die "local dir not found: $local_dir" 2

  print_remote_plan \
    "sync" \
    "$host" \
    "$remote_dir" \
    "$profile" \
    "$delete_remote" \
    "ssh mkdir -p $remote_dir" \
    "rsync $local_dir/ -> ${host}:${remote_dir%/}/"
  ssh_mkdir_args=(ssh -o ConnectTimeout=10 "$host" "mkdir -p $(printf '%q' "$remote_dir")")
  "${ssh_mkdir_args[@]}"
  rsync_args=(-avh --progress --rsh "ssh -o ConnectTimeout=10")
  if [[ "$follow_links" == true ]]; then
    rsync_args+=(-L)
  fi
  if [[ "$delete_remote" == true ]]; then
    rsync_args+=(--delete)
  fi
  rsync_args+=(
    --exclude ".git/"
    --exclude ".env"
    --exclude ".venv/"
    --exclude ".run/"
    --exclude "logs/"
    --exclude "__pycache__/"
    --exclude ".DS_Store"
    --exclude "ComfyUI/models/"
    --exclude "ComfyUI/output/"
    --exclude "ComfyUI/input/"
    --exclude "ComfyUI/temp/"
    --exclude "ComfyUI/user/"
    "${local_dir%/}/"
    "${host}:${remote_dir%/}/"
  )
  print_command rsync "${rsync_args[@]}"
  exec rsync "${rsync_args[@]}"
}

handle_remote_bootstrap() {
  host=""
  remote_dir=""
  profile=""
  uv_index_url=""
  yes=false
  while [[ $# -gt 0 ]]; do
    if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      --uv-index-url)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--uv-index-url requires a value" usage
        uv_index_url="$2"
        shift 2
        ;;
      --yes)
        yes=true
        shift
        ;;
      -h|--help)
        usage_bootstrap
        exit 0
        ;;
      *)
        usage_error "unknown bootstrap option: $1" usage_bootstrap
        ;;
    esac
  done
  require_host_dir
  require_yes "$yes"
  if [[ -n "$uv_index_url" ]]; then
    validate_url "$uv_index_url"
  fi
  require_cmd ssh
  bootstrap_args=(./scripts/local.sh bootstrap)
  bootstrap_remote_action="cd $remote_dir && $(quote_cmd "${bootstrap_args[@]}")"
  if [[ -n "$uv_index_url" ]]; then
    bootstrap_remote_action="cd $remote_dir && UV_INDEX_URL=$uv_index_url $(quote_cmd "${bootstrap_args[@]}")"
  fi
  print_remote_plan \
    "bootstrap" \
    "$host" \
    "$remote_dir" \
    "$profile" \
    "" \
    "$bootstrap_remote_action"
  if [[ -n "$uv_index_url" ]]; then
    remote_command="$(remote_cd_cmd "$remote_dir" env "UV_INDEX_URL=$uv_index_url" "${bootstrap_args[@]}")"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
  fi
  remote_command="$(remote_cd_cmd "$remote_dir" "${bootstrap_args[@]}")"
  ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
  exec "${ssh_args[@]}"
}

handle_remote_lifecycle() {
  local lifecycle_cmd="$1"
  shift
  host=""
  remote_dir=""
  profile=""
  yes=false
  while [[ $# -gt 0 ]]; do
    if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      --yes)
        yes=true
        shift
        ;;
      -h|--help)
        usage_lifecycle "$lifecycle_cmd"
        exit 0
        ;;
      *)
        usage_error "unknown ${lifecycle_cmd} option: $1" usage_lifecycle
        ;;
    esac
  done
  require_host_dir
  require_yes "$yes"
  require_cmd ssh
  lifecycle_args=(./scripts/local.sh "$lifecycle_cmd")
  print_remote_plan \
    "$lifecycle_cmd" \
    "$host" \
    "$remote_dir" \
    "$profile" \
    "" \
    "cd $remote_dir && $(quote_cmd "${lifecycle_args[@]}")"
  remote_command="$(remote_cd_cmd "$remote_dir" "${lifecycle_args[@]}")"
  ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
  exec "${ssh_args[@]}"
}

handle_remote_status() {
  host=""
  remote_dir=""
  profile=""
  while [[ $# -gt 0 ]]; do
    if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      -h|--help)
        usage_status
        exit 0
        ;;
      *)
        usage_error "unknown status option: $1" usage_status
        ;;
    esac
  done
  require_host_dir
  require_cmd ssh
  status_args=(./scripts/local.sh status)
  remote_command="$(remote_cd_cmd "$remote_dir" "${status_args[@]}")"
  ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
  exec "${ssh_args[@]}"
}

handle_remote_ready() {
  host=""
  remote_dir=""
  profile=""
  url=""
  while [[ $# -gt 0 ]]; do
    if parse_host_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      --url)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--url requires a value" usage
        url="$2"
        shift 2
        ;;
      -h|--help)
        usage_ready
        exit 0
        ;;
      *)
        usage_error "unknown ready option: $1" usage_ready
        ;;
    esac
  done
  url="${url:-$(config_value REMOTE_READY_URL)}"
  url="${url:-$DEFAULT_READY_URL}"
  require_host
  validate_url "$url"
  require_cmd ssh
  remote_command="$(remote_ready_cmd "$url")"
  ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
  exec "${ssh_args[@]}"
}

handle_remote_logs() {
  host=""
  remote_dir=""
  profile=""
  tail_lines=""
  follow=false
  while [[ $# -gt 0 ]]; do
    if parse_host_dir_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      --tail)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--tail requires a value" usage
        tail_lines="$2"
        shift 2
        ;;
      --follow)
        follow=true
        shift
        ;;
      -h|--help)
        usage_logs
        exit 0
        ;;
      *)
        usage_error "unknown logs option: $1" usage_logs
        ;;
    esac
  done
  tail_lines="${tail_lines:-$(config_value REMOTE_LOG_TAIL)}"
  tail_lines="${tail_lines:-$DEFAULT_LOG_TAIL}"
  require_host_dir
  validate_tail "$tail_lines"
  require_cmd ssh
  if [[ "$follow" == true ]]; then
    remote_command="$(remote_cd_cmd "$remote_dir" ./scripts/local.sh logs)"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
  fi
  if [[ "$tail_lines" == "all" ]]; then
    remote_command="$(remote_cd_cmd "$remote_dir" cat logs/comfyui.log)"
    ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
    exec "${ssh_args[@]}"
  fi
  remote_command="$(remote_cd_cmd "$remote_dir" tail -n "$tail_lines" logs/comfyui.log)"
  ssh_args=(ssh -o ConnectTimeout=10 "$host" "$remote_command")
  exec "${ssh_args[@]}"
}

handle_remote_tunnel() {
  host=""
  remote_dir=""
  profile=""
  local_port=""
  remote_host=""
  remote_port=""
  dry_run=false
  while [[ $# -gt 0 ]]; do
    if parse_host_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      --local-port)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--local-port requires a value" usage
        local_port="$2"
        shift 2
        ;;
      --remote-host)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--remote-host requires a value" usage
        remote_host="$2"
        shift 2
        ;;
      --remote-port)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--remote-port requires a value" usage
        remote_port="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      -h|--help)
        usage_tunnel
        exit 0
        ;;
      *)
        usage_error "unknown tunnel option: $1" usage_tunnel
        ;;
    esac
  done
  local_port="${local_port:-$(config_value REMOTE_TUNNEL_LOCAL_PORT)}"
  local_port="${local_port:-$DEFAULT_LOCAL_PORT}"
  remote_host="${remote_host:-$(config_value REMOTE_TUNNEL_REMOTE_HOST)}"
  remote_host="${remote_host:-$DEFAULT_REMOTE_HOST}"
  remote_port="${remote_port:-$(config_value REMOTE_TUNNEL_REMOTE_PORT)}"
  remote_port="${remote_port:-$DEFAULT_REMOTE_PORT}"
  require_host
  validate_port "--local-port" "$local_port"
  validate_port "--remote-port" "$remote_port"
  validate_simple_host "--remote-host" "$remote_host"
  require_cmd ssh
  ssh_args=(ssh -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -N -L "${local_port}:${remote_host}:${remote_port}" "$host")
  section "Tunnel"
  event "URL" "web" "http://127.0.0.1:${local_port}/"
  event "FORWARD" "local" "127.0.0.1:${local_port} -> ${remote_host}:${remote_port} via ${host}"
  event "HOLD" "terminal" "keep this command running while using the tunnel"
  print_command "${ssh_args[@]}"
  if [[ "$dry_run" == true ]]; then
    exit 0
  fi
  exec "${ssh_args[@]}"
}

handle_remote_gpu() {
  host=""
  remote_dir=""
  profile=""
  connect_timeout=""
  json_output=false
  while [[ $# -gt 0 ]]; do
    if parse_host_common "$@"; then shift "$consumed"; continue; fi
    case "$1" in
      --connect-timeout)
        [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "--connect-timeout requires a value" usage
        connect_timeout="$2"
        shift 2
        ;;
      --json)
        json_output=true
        shift
        ;;
      -h|--help)
        usage_gpu
        exit 0
        ;;
      *)
        usage_error "unknown gpu option: $1" usage_gpu
        ;;
    esac
  done
  connect_timeout="${connect_timeout:-$(config_value REMOTE_GPU_CONNECT_TIMEOUT)}"
  connect_timeout="${connect_timeout:-$DEFAULT_CONNECT_TIMEOUT}"
  require_host
  validate_positive_uint "--connect-timeout" "$connect_timeout"
  require_cmd ssh
  require_cmd python3
  formatter_args=("$ROOT_DIR/scripts/lib/remote_gpu_format.py" --host "$host")
  if [[ "$json_output" == true ]]; then
    formatter_args+=(--json)
  fi
  ssh_args=(ssh -o ConnectTimeout="$connect_timeout" "$host" "$(remote_gpu_snapshot_cmd)")
  set +e
  snapshot="$("${ssh_args[@]}")"
  ssh_status=$?
  set -e
  if [[ "$ssh_status" -ne 0 ]]; then
    exit "$ssh_status"
  fi
  printf '%s\n' "$snapshot" | python3 "${formatter_args[@]}"
}
