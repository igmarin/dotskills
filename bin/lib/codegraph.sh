# CodeGraph setup helper.
#
# Usage: . "$LIB/codegraph.sh"
#
# Globals this file reads (caller must set):
#   RUN_CODEGRAPH
#   CODEGRAPH_BIN
#   FORCE_REBUILD
#
# Returns:
#   0 if skipped or ran successfully
#   1 if init/sync failed
#   2 if synced (only when FORCE_REBUILD and index existed)
#   3 if skipped because RUN_CODEGRAPH is false or CODEGRAPH_BIN is empty

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

codegraph_setup() {
  local repo="${1%/}"

  if [ "$RUN_CODEGRAPH" != true ] || [ -z "$CODEGRAPH_BIN" ]; then
    return 3
  fi

  if [ ! -d "$repo/.codegraph" ]; then
    echo "[*] [CodeGraph] Initializing index..."
    if "$CODEGRAPH_BIN" init "$repo"; then
      return 0
    else
      return 1
    fi
  elif [ "$FORCE_REBUILD" = true ]; then
    echo "[*] [CodeGraph] Syncing index..."
    if "$CODEGRAPH_BIN" sync "$repo"; then
      return 2
    else
      return 1
    fi
  else
    echo "[✓] [CodeGraph] Already initialized."
    return 0
  fi
}
