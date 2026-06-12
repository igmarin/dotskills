#!/usr/bin/env bash
#
# dotskills install.sh
#
# Bootstraps the full igmarin agent skill ecosystem into ~/.agents/skills/.
#
# Sources installed (in priority order — later copies override earlier on collision):
#   5. owainlewis/blueprint        (minimal SDLC baseline)
#   4. addyosmani/agent-skills     (general engineering skills)
#   3. google/skills               (Google Cloud + Gemini skills)
#   3. cloudflare/skills           (Cloudflare Workers, Agents SDK, Durable Objects)
#   2. igmarin/agnostic-planning-skills  (language-agnostic planning)
#   2. igmarin/ruby-core-skills          (shared Ruby process skills)
#   2. igmarin/rails-agent-skills        (Rails-specific skills)
#   1. dotskills/skills/           (personal glue skills — always win)
#
# Collision policy: higher priority overwrites lower.
# Your personal skills (this repo) always win.
#
# Usage:
#   ./install.sh           — install/update everything
#   ./install.sh --dry-run — show what would happen, no changes
#   ./install.sh --help    — show this message

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

DOTSKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$HOME/.dotskills/sources"
TARGET_DIR="$HOME/.agents/skills"
DRY_RUN=false

# ── Sources (priority order: lowest first — higher priority sources are listed last) ──

declare -a SOURCE_REPOS=(
  "owainlewis/blueprint|https://github.com/owainlewis/blueprint.git|skills"
  "addyosmani/agent-skills|https://github.com/addyosmani/agent-skills.git|skills"
  "google/skills|https://github.com/google/skills.git|skills"
  "cloudflare/skills|https://github.com/cloudflare/skills.git|skills"
  "igmarin/agnostic-planning-skills|https://github.com/igmarin/agnostic-planning-skills.git|skills"
  "igmarin/ruby-core-skills|https://github.com/igmarin/ruby-core-skills.git|skills"
  "igmarin/rails-agent-skills|https://github.com/igmarin/rails-agent-skills.git|skills"
)

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
info() { echo ""; echo "▸ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }

run() {
  if $DRY_RUN; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# ── Args ─────────────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help)
      sed -n '2,/^set /p' "$0" | grep '^#' | sed 's/^# \?//'
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

# Create directories
run mkdir -p "$SOURCES_DIR"
run mkdir -p "$TARGET_DIR"

# Install each source repo
for entry in "${SOURCE_REPOS[@]}"; do
  IFS='|' read -r slug url skills_subdir <<< "$entry"
  local_path="$SOURCES_DIR/$slug"

  info "[$slug]"

  # Clone or update
  if [ -d "$local_path/.git" ]; then
    log "Updating $slug..."
    if $DRY_RUN; then
      log "[dry-run] git -C $local_path pull --ff-only"
    else
      git -C "$local_path" pull --ff-only --quiet 2>&1 | sed 's/^/  /' || warn "Pull failed — using cached version"
    fi
  else
    log "Cloning $slug..."
    run git clone --quiet --depth 1 "$url" "$local_path"
  fi

  # Copy skills into target
  skills_path="$local_path/$skills_subdir"
  if [ ! -d "$skills_path" ]; then
    warn "No $skills_subdir/ directory found in $slug — skipping"
    continue
  fi

  copied=0
  overwritten=0
  for skill_dir in "$skills_path"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    dest="$TARGET_DIR/$skill_name"

    if [ -d "$dest" ]; then
      run cp -r "$skill_dir" "$TARGET_DIR/"
      (( overwritten++ )) || true
    else
      run cp -r "$skill_dir" "$TARGET_DIR/"
      (( copied++ )) || true
    fi
  done

  ok "$((copied + overwritten)) skills installed ($overwritten overwritten from lower-priority source)"
done

# Install personal skills from this repo (highest priority — always last)
info "[dotskills/skills — personal]"
personal_skills_dir="$DOTSKILLS_DIR/skills"

if [ -d "$personal_skills_dir" ]; then
  copied=0
  for skill_dir in "$personal_skills_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    run cp -r "$skill_dir" "$TARGET_DIR/"
    (( copied++ )) || true
  done
  ok "$copied personal skill(s) installed (these always win over all sources)"
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
