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
