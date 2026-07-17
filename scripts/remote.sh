#!/usr/bin/env bash
# remote.sh - thin SSH orchestration entry for explicit remote hosts

set -euo pipefail

REMOTE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$REMOTE_SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/remote/usage.sh
source "$REMOTE_SCRIPT_DIR/remote/usage.sh"
# shellcheck source=scripts/remote/core.sh
source "$REMOTE_SCRIPT_DIR/remote/core.sh"
# shellcheck source=scripts/remote/models.sh
source "$REMOTE_SCRIPT_DIR/remote/models.sh"
# shellcheck source=scripts/remote/actions.sh
source "$REMOTE_SCRIPT_DIR/remote/actions.sh"

cmd="${1:-}"
case "$cmd" in
  -h|--help|"")
    usage
    [[ -n "$cmd" ]] && exit 0 || exit 2
    ;;
esac
shift

case "$cmd" in
  sync)
    handle_remote_sync "$@"
    ;;
  bootstrap)
    handle_remote_bootstrap "$@"
    ;;
  start|stop|restart)
    handle_remote_lifecycle "$cmd" "$@"
    ;;
  status)
    handle_remote_status "$@"
    ;;
  ready)
    handle_remote_ready "$@"
    ;;
  logs)
    handle_remote_logs "$@"
    ;;
  models)
    handle_remote_models "$@"
    ;;
  tunnel)
    handle_remote_tunnel "$@"
    ;;
  gpu)
    handle_remote_gpu "$@"
    ;;
  *)
    usage_error "unknown command: $cmd" usage
    ;;
esac
