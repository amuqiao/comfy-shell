#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/common.sh must be sourced, not executed directly\n' >&2
  exit 2
fi

COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "${COMMON_LIB_DIR}/.." && pwd)"
# shellcheck disable=SC2034
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC2034
DEFAULT_CONFIG_FILE="$ROOT_DIR/.env"
# shellcheck disable=SC2034
CONFIG_FILE="$DEFAULT_CONFIG_FILE"

die() {
  local message="$1"
  local code="${2:-1}"
  printf 'ERROR: %s\n' "$message" >&2
  exit "$code"
}

usage_error() {
  printf 'ERROR: %s\n\n' "$1" >&2
  "$2" >&2
  exit 2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'ERROR: missing required command: %s\n' "$cmd" >&2
    exit 2
  fi
}

section() {
  printf '\n===== %s =====\n' "$1"
}

event() {
  printf '%-10s %-18s %s\n' "$1" "$2" "${3:-}"
}

print_command() {
  printf '命令:\n'
  printf ' %q' "$@"
  printf '\n'
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
    return
  fi

  local dir
  local base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  (cd "$dir" && printf '%s/%s\n' "$(pwd)" "$base")
}

env_value_from() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
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
  ' "$file"
}

set_config_file() {
  local file="$1"
  case "$file" in
    /*) CONFIG_FILE="$file" ;;
    *) CONFIG_FILE="$ROOT_DIR/$file" ;;
  esac
}

require_config_file() {
  [[ -f "$CONFIG_FILE" ]] || die "config file not found: $CONFIG_FILE" 2
}

config_value() {
  local key="$1"
  local decl
  decl="$(declare -p "$key" 2>/dev/null || true)"
  if [[ "$decl" =~ ^declare\ -[^[:space:]]*x[^[:space:]]*\ $key(=|$) ]]; then
    printf '%s' "${!key}"
    return
  fi
  env_value_from "$key" "$CONFIG_FILE"
}

required_config_value() {
  local key="$1"
  local value
  value="$(config_value "$key")"
  [[ -n "$value" ]] || die "missing required config: $key in process environment or $CONFIG_FILE" 2
  printf '%s' "$value"
}

repo_path() {
  local path="$1"
  case "$path" in
    /*) printf '%s' "$path" ;;
    *) printf '%s/%s' "$ROOT_DIR" "$path" ;;
  esac
}
