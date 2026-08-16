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

# Append pattern to file only if it is not already present.
add_if_missing() {
  local pattern="$1"
  local file="$2"
  if ! grep -Fxq "$pattern" "$file" 2>/dev/null; then
    echo "$pattern" >> "$file"
  fi
}

# Return 0 if dir looks like a project repo.
is_project_dir() {
  local dir="${1%/}"
  [ -d "$dir/.git" ] || [ -f "$dir/.serena/project.yml" ] || [ -f "$dir/Cargo.toml" ] || [ -f "$dir/Gemfile" ] || [ -f "$dir/package.json" ]
}

# Print child directory names under parent that may be project repos.
list_child_repo_names() {
  local parent="${1%/}"
  local d name
  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "${d%/}")"
    [[ "$name" == .* ]] && continue
    printf '%s\n' "$name"
  done
}
