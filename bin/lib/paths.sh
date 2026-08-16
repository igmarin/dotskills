# Shared path helpers. Source from a file that already knows this path
# (bin/*.sh → ./lib/paths.sh). Do not source this to *find* the repo —
# a symlink outside the tree cannot see this file until the caller
# follows the link.
#
# Usage:  . "$BIN_DIR/lib/paths.sh"
#         repo_root="$(cd "$(script_dir_of "${BASH_SOURCE[0]}")/.." && pwd)"
#
# shellcheck disable=SC2094  # cd follows symlinks, which is intentional here

script_dir_of() {
  local script_src="$1"
  local script_dir
  local loop_count=0
  local max_loops=10
  
  while [ -L "$script_src" ]; do
    loop_count=$((loop_count + 1))
    if [ "$loop_count" -gt "$max_loops" ]; then
      echo "Error: circular symlink detected in path resolution" >&2
      exit 1
    fi
    
    script_dir="$(cd "$(dirname "$script_src")" 2>/dev/null && pwd)" || {
      echo "Error: cannot resolve symlink directory: $script_src" >&2
      exit 1
    }
    script_src="$(readlink "$script_src" 2>/dev/null)" || {
      echo "Error: cannot read symlink: $script_src" >&2
      exit 1
    }
    [[ "$script_src" != /* ]] && script_src="$script_dir/$script_src"
  done
  cd "$(dirname "$script_src")" && pwd
}
