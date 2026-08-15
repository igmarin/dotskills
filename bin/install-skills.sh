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
#   --only=LIST               Comma-separated slugs (e.g., --only=igmarin/rails-agent-skills)
#   --with-community          npx-install third-party collections (not clone)
#   --with=elixir-phoenix-skills
#                             Work-only: also install igmarin/elixir-phoenix-skills
#   --with-rs-guard           Also copy skills/setup-rs-guard (personal review runbook)
#   --uninstall               Remove target directory contents
#   --clean                   Alias for --uninstall
#   --help                    Show this message
#
# Default sources (later copies override earlier on collision):
#   igmarin/agnostic-planning-skills
#   igmarin/ruby-core-skills
#   igmarin/rails-agent-skills
#   dotskills/skills/          (generic personal skills — always last, always win)
#                              setup-rs-guard is skipped unless --with-rs-guard
#
# Usage:
#   ./install.sh                              — owned repos + generic personal skills
#   ./install.sh --with-community             — also npx third-party collections
#   ./install.sh --with=elixir-phoenix-skills — also elixir (work machine)
#   ./install.sh --with-rs-guard              — also setup-rs-guard
#   ./install.sh --dry-run
#   ./install.sh --verbose
#   ./install.sh --only=slug1,slug2
#   ./install.sh --uninstall
#   ./install.sh --help

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

DOTSKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES_DIR="$HOME/.dotskills/sources"
TARGET_DIR="$HOME/.agents/skills"
DRY_RUN=false
VERBOSE=false
UNINSTALL=false
ONLY_SLUG=""
WITH_COMMUNITY=false
WITH_RS_GUARD=false
WITH_ELIXIR=false

# Default: repos you author. Elixir is opt-in. Community is npx, not clone.
declare -a OWNED_REPOS=(
  "igmarin/agnostic-planning-skills|https://github.com/igmarin/agnostic-planning-skills.git|skills"
  "igmarin/ruby-core-skills|https://github.com/igmarin/ruby-core-skills.git|skills"
  "igmarin/rails-agent-skills|https://github.com/igmarin/rails-agent-skills.git|skills"
)

# Collections: npx skills install -g <slug> --all
declare -a NPX_COMMUNITY=(
  "owainlewis/agent-skills"
  "owainlewis/blueprint"
  "mattpocock/skills"
  "dietrichgebert/ponytail"
)

ELIXIR_REPO="igmarin/elixir-phoenix-skills|https://github.com/igmarin/elixir-phoenix-skills.git|skills"

# Built after flag parse: owned + elixir (if any)
declare -a SOURCE_REPOS=()

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
info() { echo ""; echo "▸ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }

log_cmd() {
  if $VERBOSE; then
    echo "  [verbose] $*"
  fi
}

run() {
  if $DRY_RUN; then
    echo "  [dry-run] $*"
    return 0
  fi
  log_cmd "$*"
  "$@"
}

check_dependencies() {
  local missing=()
  local cmd
  local required=(git)
  if $WITH_COMMUNITY; then
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
  local slug
  info "[npx community collections]"
  for slug in "${NPX_COMMUNITY[@]}"; do
    if ! should_process_slug "$slug"; then
      log "(skipping $slug — not in --only list)"
      continue
    fi
    log "npx skills install -g $slug --all"
    run npx --yes skills install -g "$slug" --all
  done
  ok "community collections via npx"
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
  read -p "Continue? [y/N] " -n 1 -r
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

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --verbose) VERBOSE=true ;;
    --uninstall|--clean) UNINSTALL=true ;;
    --only=*)
      ONLY_SLUG="${arg#*=}"
      # Validate --only input for path traversal attacks
      case "$ONLY_SLUG" in
        *'..'*)
          echo "Error: Path traversal not allowed in --only: $ONLY_SLUG" >&2
          exit 1
          ;;
      esac
      ;;
    --with-community) WITH_COMMUNITY=true ;;
    --with-rs-guard) WITH_RS_GUARD=true ;;
    --with=elixir-phoenix-skills|--with=igmarin/elixir-phoenix-skills)
      WITH_ELIXIR=true
      ;;
    --with=*)
      echo "Unknown extra: ${arg#*=}" >&2
      echo "Known extras: elixir-phoenix-skills" >&2
      echo "Also: --with-community  --with-rs-guard" >&2
      exit 1
      ;;
    --help)
      cat <<'EOF'
dotskills install.sh

Installs skills you author into ~/.agents/skills/.
Third-party collections: npx skills install -g <slug> --all
  (--with-community runs those). Do not clone them here.
./install.sh copies owned trees and will overwrite a same-named skill from npx.

Features:
  --dry-run      Show what would happen, no changes
  --verbose      Log commands being executed
  --only=LIST    Comma-separated slugs (e.g., --only=igmarin/rails-agent-skills)
  --with-community
                 npx-install collections (not clone):
                 owainlewis/agent-skills, owainlewis/blueprint,
                 mattpocock/skills, dietrichgebert/ponytail
  --with=elixir-phoenix-skills
                 Work-only: also install igmarin/elixir-phoenix-skills
  --with-rs-guard
                 Also copy skills/setup-rs-guard (personal review runbook)
  --uninstall    Remove target directory contents
  --clean        Alias for --uninstall
  --help         Show this message

Default sources (later copies override earlier on collision):
  igmarin/agnostic-planning-skills
  igmarin/ruby-core-skills
  igmarin/rails-agent-skills
  dotskills/skills/   (generic personal skills — always last, always win)
                      setup-rs-guard is skipped unless --with-rs-guard

Usage:
  ./install.sh                              — owned repos + generic personal skills
  ./install.sh --with-community             — also npx third-party collections
  ./install.sh --with=elixir-phoenix-skills — also elixir (work machine)
  ./install.sh --with-rs-guard              — also setup-rs-guard
  ./install.sh --dry-run
  ./install.sh --verbose
  ./install.sh --only=slug1,slug2
  ./install.sh --uninstall
  ./install.sh --help
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
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

# Lowest priority first. npx community (opt-in) < owned < elixir (opt-in) < personal.
SOURCE_REPOS=()
SOURCE_REPOS+=("${OWNED_REPOS[@]}")
if $WITH_ELIXIR; then
  SOURCE_REPOS+=("$ELIXIR_REPO")
fi

run mkdir -p "$SOURCES_DIR"
run mkdir -p "$TARGET_DIR"

if $WITH_COMMUNITY; then
  install_community_via_npx
fi

# Install each source repo
for entry in "${SOURCE_REPOS[@]}"; do
  # Parse entry without polluting global IFS
  slug=$(printf '%s' "$entry" | cut -d'|' -f1)
  url=$(printf '%s' "$entry" | cut -d'|' -f2)
  skills_subdir=$(printf '%s' "$entry" | cut -d'|' -f3)
  
  local_path="${SOURCES_DIR}/${slug}"
  
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
    
    if [ -d "$dest" ]; then
      run cp -r "$skill_dir" "${TARGET_DIR}/"
      (( overwritten++ )) || true
    else
      run cp -r "$skill_dir" "${TARGET_DIR}/"
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


