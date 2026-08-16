# Shared helper functions for dotskills scripts.
# Source this from any script that needs logging, dry-run wrappers, etc.
#
# Usage: . "$LIB/common.sh"
#
# Depends on globals:
#   VERBOSE  (default: false)
#   DRY_RUN  (default: false)

log()  { echo "  $*"; }
info() { echo ""; echo "▸ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }

log_cmd() {
  if ${VERBOSE:-false}; then
    echo "  [verbose] $*"
  fi
}

run() {
  if ${DRY_RUN:-false}; then
    echo "  [dry-run] $*"
    return 0
  fi
  log_cmd "$*"
  "$@"
}
