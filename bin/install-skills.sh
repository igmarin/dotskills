#!/usr/bin/env bash
#
# dotskills install.sh
#
# Installs skills you author into ~/.agents/skills/. Third-party collections
# belong to npx (`npx skills install -g <slug> --all`). This script copies
# owned trees and will overwrite a same-named skill that npx put there.
#
# Features:
#   --dry-run                 Show what would happen, no changes
#   --verbose                 Log commands being executed
#   --repo owner/repo         Repeatable; override default owned repo list
#   --only=LIST               Comma-separated slugs (e.g., --only=igmarin/rails-agent-skills)
#   --npx owner/repo          Repeatable; npx-install a skill collection
#   --with=elixir-phoenix-skills
#                             Work-only: also install igmarin/elixir-phoenix-skills
#   --with-rs-guard           Also copy skills/setup-rs-guard (personal review runbook)
#   --uninstall               Remove target directory contents
#   --clean                   Alias for --uninstall
#   --help                    Show this message
#
# Default sources (later copies override earlier on collision).
# Read from dotskills.toml and ~/.dotskills/config.toml; hard-coded values are the fallback:
#   igmarin/agnostic-planning-skills
#   igmarin/ruby-core-skills
#   igmarin/rails-agent-skills
#   dotskills/skills/          (generic personal skills — always last, always win)
#                              setup-rs-guard is skipped unless --with-rs-guard
#
# Usage:
#   ./install.sh                              — owned repos + generic personal skills
#   ./install.sh --npx owainlewis/blueprint   — also npx-install that collection
#   ./install.sh --npx owner/repo             — npx-install a custom collection
#   ./install.sh --with=elixir-phoenix-skills — also elixir (work machine)
#   ./install.sh --with-rs-guard              — also setup-rs-guard
#   ./install.sh --dry-run
#   ./install.sh --verbose
#   ./install.sh --only=slug1,slug2
#   ./install.sh --uninstall
#   ./install.sh --help

set -euo pipefail

# ── Paths and shared helpers ─────────────────────────────────────────────────

# shellcheck source=lib/paths.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=lib/config.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/config.sh"

DOTSKILLS_DIR="$(cd "$(script_dir_of "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES_DIR="$HOME/.dotskills/sources"
TARGET_DIR="$HOME/.agents/skills"
DRY_RUN=false
VERBOSE=false
UNINSTALL=false
ONLY_SLUG=""
WITH_RS_GUARD=false
WITH_ELIXIR=false
declare -a REPO_OVERRIDES=()
declare -a NPX_OVERRIDES=()

# Load repo and user config; hardcoded defaults are the fallback.
load_dotskills_config "$DOTSKILLS_DIR"

# Default: repos you author. Elixir is opt-in. Community is npx, not clone.
if [ "${#OWNED_REPOS[@]}" -eq 0 ]; then
  OWNED_REPOS=(
    "igmarin/agnostic-planning-skills|https://github.com/igmarin/agnostic-planning-skills.git|skills"
    "igmarin/ruby-core-skills|https://github.com/igmarin/ruby-core-skills.git|skills"
    "igmarin/rails-agent-skills|https://github.com/igmarin/rails-agent-skills.git|skills"
  )
fi

# Default npx skill collections (shown pre-selected in the TUI as recommended).
if [ "${#NPX_COMMUNITY[@]}" -eq 0 ]; then
  NPX_COMMUNITY=(
    "igmarin/agnostic-planning-skills"
    "igmarin/ruby-core-skills"
    "igmarin/rails-agent-skills"
    "owainlewis/agent-skills"
    "owainlewis/blueprint"
    "mattpocock/skills"
    "dietrichgebert/ponytail"
  )
fi

ELIXIR_REPO="igmarin/elixir-phoenix-skills|https://github.com/igmarin/elixir-phoenix-skills.git|skills"

# Built after flag parse: owned + elixir (if any)
declare -a SOURCE_REPOS=()

# ── Helpers ──────────────────────────────────────────────────────────────────

check_dependencies() {
  local missing=()
  local cmd
  local required=(git)
  if [ "${#NPX_OVERRIDES[@]}" -gt 0 ]; then
    required+=(npx)
  fi
  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing+=("$cmd")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Fatal: Missing required dependencies: ${missing[*]}" >&2
    exit 1
  fi
}

is_dirty() {
  # Returns 0 (true) if git repo has uncommitted changes, 1 otherwise
  # Silently returns 1 if $1 is not a git repo or git command fails
  git -C "$1" status --porcelain 2>/dev/null | grep -q .
}

validate_only_list() {
  local IFS=',' slug
  [ -z "$ONLY_SLUG" ] && return 0
  for slug in $ONLY_SLUG; do
    if ! valid_slug "$slug"; then
      echo "Error: invalid --only slug (expected owner/name): $slug" >&2
      exit 1
    fi
  done
}

# $1 = validated slug or existing path to check under SOURCES_DIR
# Resolves real paths with -P to prevent symlink attacks and checks containment
assert_under_sources() {
  local slug_or_path="$1"
  local sources_resolved
  local target
  
  # Resolve SOURCES_DIR to its real physical location to prevent symlink attacks.
  # In dry-run the directory may not exist yet, so fall back to the unresolved path.
  if ! sources_resolved="$(cd "$SOURCES_DIR" 2>/dev/null && pwd -P)"; then
    if $DRY_RUN; then
      sources_resolved="$SOURCES_DIR"
    else
      echo "Error: cannot resolve SOURCES_DIR: $SOURCES_DIR" >&2
      exit 1
    fi
  fi
  
  # If the argument is an existing path, resolve its physical location;
  # otherwise construct the path from the validated slug.
  if [ -e "$slug_or_path" ]; then
    target="$(cd "$slug_or_path" 2>/dev/null && pwd -P)" || {
      echo "Error: cannot resolve path: $slug_or_path" >&2
      exit 1
    }
  else
    target="${sources_resolved}/${slug_or_path}"
  fi
  
  if [[ "$target" != "$sources_resolved"/* ]]; then
    echo "Error: refusing path outside $SOURCES_DIR: $slug_or_path (resolved to $target)" >&2
    exit 1
  fi
}

should_process_slug() {
  local slug="$1"
  local IFS=','
  
  if [ -z "$ONLY_SLUG" ]; then
    return 0
  fi
  
  for filter in $ONLY_SLUG; do
    if [ "$slug" = "$filter" ]; then
      return 0
    fi
  done
  
  return 1
}

install_community_via_npx() {
  local -a selected=()
  if [ "${#NPX_OVERRIDES[@]}" -gt 0 ]; then
    selected=("${NPX_OVERRIDES[@]}")
  else
    selected=("${NPX_COMMUNITY[@]}")
  fi

  local slug
  info "[npx skill collections]"
  for slug in "${selected[@]}"; do
    if ! valid_slug "$slug"; then
      echo "Error: invalid npx slug: $slug" >&2
      exit 1
    fi
    if ! should_process_slug "$slug"; then
      log "(skipping $slug — not in --only list)"
      continue
    fi
    log "npx skills install -g $slug --all"
    run npx --yes skills install -g "$slug" --all
  done
  ok "skill collections via npx"
}

uninstall_skills() {
  if [ -z "$TARGET_DIR" ] || [ ! -d "$TARGET_DIR" ]; then
    warn "Target directory does not exist — nothing to uninstall"
    return 0
  fi
  
  # Safety check: refuse to remove root or home directories
  if [ "$TARGET_DIR" = "/" ] || [[ "$TARGET_DIR" == "$HOME" ]]; then
    echo "Fatal: Refusing to remove root or home directory" >&2
    exit 1
  fi
  
  local count
  count=$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  
  echo "This will remove $count skill directories from $TARGET_DIR"
  REPLY=""
  if ! read -r -p "Continue? [y/N] " -n 1; then
    echo
    echo "Cancelled (read failed or EOF)."
    return 0
  fi
  echo
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    return 0
  fi
  
  # Use find with explicit path for safer deletion
  run find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
  ok "Skills uninstalled"
}

# ── Args ─────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --uninstall|--clean) UNINSTALL=true; shift ;;
    --only=*)
      ONLY_SLUG="${1#*=}"
      validate_only_list
      shift
      ;;
    --repo)
      if [ -z "${2:-}" ]; then
        echo "Error: --repo needs an owner/repo slug" >&2
        exit 1
      fi
      if ! valid_slug "$2"; then
        echo "Error: invalid --repo slug (expected owner/name): $2" >&2
        exit 1
      fi
      REPO_OVERRIDES+=("$2")
      shift 2
      ;;
    --repo=*)
      slug="${1#*=}"
      if ! valid_slug "$slug"; then
        echo "Error: invalid --repo slug (expected owner/name): $slug" >&2
        exit 1
      fi
      REPO_OVERRIDES+=("$slug")
      shift
      ;;
    --npx)
      if [ -z "${2:-}" ]; then
        echo "Error: --npx needs an owner/repo slug" >&2
        exit 1
      fi
      if ! valid_slug "$2"; then
        echo "Error: invalid --npx slug (expected owner/name): $2" >&2
        exit 1
      fi
      NPX_OVERRIDES+=("$2")
      shift 2
      ;;
    --npx=*)
      slug="${1#*=}"
      if ! valid_slug "$slug"; then
        echo "Error: invalid --npx slug (expected owner/name): $slug" >&2
        exit 1
      fi
      NPX_OVERRIDES+=("$slug")
      shift
      ;;
    --with-rs-guard) WITH_RS_GUARD=true; shift ;;
    --with=elixir-phoenix-skills|--with=igmarin/elixir-phoenix-skills)
      WITH_ELIXIR=true
      shift
      ;;
    --with=*)
      echo "Unknown extra: ${1#*=}" >&2
      echo "Known extras: elixir-phoenix-skills" >&2
      echo "Also: --with-rs-guard  --npx owner/repo" >&2
      exit 1
      ;;
    --help|-h)
      cat <<'EOF'
dotskills install.sh

Installs skills you author into ~/.agents/skills/.
Third-party collections: npx skills install -g <slug> --all
  (--npx owner/repo selects those). Do not clone them here.
./install.sh copies owned trees and will overwrite a same-named skill from npx.

Features:
  --dry-run      Show what would happen, no changes
  --verbose      Log commands being executed
  --repo owner/repo
                 Repeatable; use instead of the default owned repo list.
                 Example: --repo igmarin/ruby-core-skills
  --npx owner/repo
                 Repeatable; npx-install a skill collection.
                 Example: --npx owainlewis/blueprint
  --only=LIST    Comma-separated slugs (e.g., --only=igmarin/rails-agent-skills)
  --with=elixir-phoenix-skills
                 Work-only: also install igmarin/elixir-phoenix-skills
  --with-rs-guard
                 Also copy skills/setup-rs-guard (personal review runbook)
  --uninstall    Remove target directory contents
  --clean        Alias for --uninstall
  --help         Show this message

Default sources (later copies override earlier on collision).
Read from dotskills.toml and ~/.dotskills/config.toml; hard-coded values are the fallback:
  igmarin/agnostic-planning-skills
  igmarin/ruby-core-skills
  igmarin/rails-agent-skills
  dotskills/skills/   (generic personal skills — always last, always win)
                      setup-rs-guard is skipped unless --with-rs-guard

Recommended npx collections (selectable in the TUI; not installed by default):
  igmarin/agnostic-planning-skills
  igmarin/ruby-core-skills
  igmarin/rails-agent-skills
  owainlewis/agent-skills
  owainlewis/blueprint
  mattpocock/skills
  dietrichgebert/ponytail

Usage:
  ./install.sh                              — owned repos + generic personal skills
  ./install.sh --npx owainlewis/blueprint   — also npx-install that collection
  ./install.sh --npx owner/repo             — npx-install a custom collection
  ./install.sh --with=elixir-phoenix-skills — also elixir (work machine)
  ./install.sh --with-rs-guard              — also setup-rs-guard
  ./install.sh --repo owner/repo            — override owned repos
  ./install.sh --dry-run
  ./install.sh --verbose
  ./install.sh --only=slug1,slug2
  ./install.sh --uninstall
  ./install.sh --help
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Main ─────────────────────────────────────────────────────────────────────

echo ""
echo "dotskills — agent skill ecosystem installer"
echo "============================================"
$DRY_RUN && echo "  (dry-run mode — no changes will be made)"
$VERBOSE && echo "  (verbose mode — commands will be logged)"

check_dependencies

if $UNINSTALL; then
  uninstall_skills
  exit 0
fi

# Lowest priority first. npx collections (opt-in) < selected repos or owned < elixir (opt-in) < personal.
SOURCE_REPOS=()

if [ "${#REPO_OVERRIDES[@]}" -gt 0 ]; then
  for slug in "${REPO_OVERRIDES[@]}"; do
    SOURCE_REPOS+=("${slug}|https://github.com/${slug}.git|skills")
  done
else
  SOURCE_REPOS+=("${OWNED_REPOS[@]}")
fi

if $WITH_ELIXIR; then
  SOURCE_REPOS+=("$ELIXIR_REPO")
fi

run mkdir -p "$SOURCES_DIR"
run mkdir -p "$TARGET_DIR"

if [ "${#NPX_OVERRIDES[@]}" -gt 0 ]; then
  install_community_via_npx
fi

# Install each source repo
for entry in "${SOURCE_REPOS[@]}"; do
  # Parse entry without polluting global IFS
  slug=$(printf '%s' "$entry" | cut -d'|' -f1)
  url=$(printf '%s' "$entry" | cut -d'|' -f2)
  skills_subdir=$(printf '%s' "$entry" | cut -d'|' -f3)

  if ! valid_slug "$slug"; then
    echo "Error: refusing invalid source slug: $slug" >&2
    exit 1
  fi
  local_path="${SOURCES_DIR}/${slug}"
  assert_under_sources "$local_path"
  
  # Skip if --only filter doesn't match
  if ! should_process_slug "$slug"; then
    log "(skipping $slug — not in --only list)"
    continue
  fi
  
  info "[$slug]"
  
  # Clone or update
  if [ -d "${local_path}/.git" ]; then
    log "Updating $slug..."
    
    if is_dirty "$local_path" 2>/dev/null; then
      log "Repository has uncommitted changes — using fetch + hard reset"
      if ! run git -C "$local_path" fetch --quiet origin 2>&1; then
        warn "Fetch failed — using cached version"
        continue
      fi
      run git -C "$local_path" reset --hard --quiet FETCH_HEAD
    else
      run git -C "$local_path" pull --ff-only --quiet || warn "Pull failed — using cached version"
    fi
  else
    log "Cloning $slug..."
    run git clone --quiet --depth 1 "$url" "$local_path"
  fi
  
  # Copy skills into target
  skills_path="${local_path}/${skills_subdir}"
  if [ ! -d "$skills_path" ]; then
    warn "No ${skills_subdir}/ directory found in $slug — skipping"
    continue
  fi
  
  copied=0
  overwritten=0
  for skill_dir in "${skills_path}"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    dest="${TARGET_DIR}/${skill_name}"
    
    # Record whether dest existed before copy (for accurate counting)
    dest_existed=false
    [ -d "$dest" ] && dest_existed=true
    
    run cp -r "$skill_dir" "${TARGET_DIR}/"
    if $dest_existed; then
      (( overwritten++ )) || true
    else
      (( copied++ )) || true
    fi
  done
  
  ok "$((copied + overwritten)) skills installed ($overwritten overwritten from lower-priority source)"
done

# Install personal skills from this repo (highest priority — always last)
# Personal skills are always installed regardless of --only filter
info "[dotskills/skills — personal]"
personal_skills_dir="${DOTSKILLS_DIR}/skills"

if [ -d "$personal_skills_dir" ]; then
  copied=0
  skipped=0
  for skill_dir in "${personal_skills_dir}"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    if [ "$skill_name" = "setup-rs-guard" ] && ! $WITH_RS_GUARD; then
      log "(skipping setup-rs-guard — pass --with-rs-guard to install)"
      (( skipped++ )) || true
      continue
    fi
    run cp -r "$skill_dir" "${TARGET_DIR}/"
    (( copied++ )) || true
  done
  ok "$copied personal skill(s) installed (these always win over all sources)"
  if [ "$skipped" -gt 0 ]; then
    log "$skipped optional personal skill(s) skipped"
  fi
else
  warn "No skills/ directory found in dotskills — nothing personal to install"
fi

# Summary
echo ""
echo "============================================"
echo "Done."
echo ""
echo "Skills installed to: $TARGET_DIR"
echo "Source clones at:    $SOURCES_DIR"
echo ""
echo "To update all skills in the future, run this script again."


