#!/usr/bin/env bash
# ==============================================================================
# setup-ai-tools.sh
#
# Unified setup & configuration for Code Intelligence tools across all repositories
# and AI clients:
#   - Serena (LSP AST analysis, symbol navigation, diagnostics, refactoring, memories)
#   - CodeGraph (Fast SQLite AST knowledge graph + call graph)
#   - Graphify (Full architecture knowledge graph extracted via DeepSeek deepseek-v4-pro)
#
# Auto-install (skipped with --no-install). uv is installed first if Serena or
# Graphify need it and it is not on PATH.
#
#   Tool        If missing / when run
#   ----------  --------------------------------------------------------------
#   Serena      uv tool install -p 3.13 serena-agent
#   Graphify    uv tool install --force --reinstall "graphifyy[mcp,openai]"
#               (openai extra required for DeepSeek extract)
#   CodeGraph   npm install -g @colbymchenry/codegraph
#               init only if .codegraph is missing; skip if it exists;
#               --force + existing index → codegraph sync (not init, not index)
#   gum         brew install gum   (TUI only; asked if missing, then stop)
#
# Interactive (gum): run with no mode flags in a terminal. Pick tools and
# repos with space-to-toggle (same as the tool list — not one-by-one).
# If gum is missing you can install it and stop (re-run for the TUI) or
# continue without it. Flags still work for scripts and CI.
#
# Supported AI Clients:
#   - Devin (global + local MCP, skills, permissions)
#   - Cline (CLI + VS Code extension, MCP configs, clinerules)
#   - Grok (xAI Grok Build CLI: ~/.grok/config.toml + per-project
#     .grok/config.toml MCP, hooks, and .grok/rules)
#   - Zed (global + project context_servers)
#   - Aider (memories + conventions)
#
# Usage:
#   ./bin/setup-ai-tools.sh [OPTIONS] [TARGET_DIR]
#
# Examples:
#   ./bin/setup-ai-tools.sh                           # Configure all repos in current dir
#   ./bin/setup-ai-tools.sh /path/to/Projects         # Configure all repos in folder
#   ./bin/setup-ai-tools.sh /path/to/Projects/my-repo # Configure single repo
#   ./bin/setup-ai-tools.sh --force                   # Graphify re-extract; CodeGraph sync
#   ./bin/setup-ai-tools.sh --serena-only             # Run only Serena setup
#   ./bin/setup-ai-tools.sh --codegraph-only          # Run only CodeGraph setup
#   ./bin/setup-ai-tools.sh --graphify-only           # Run only Graphify extraction
#   ./bin/setup-ai-tools.sh --no-install              # Do not auto-install missing tools
#   ./bin/setup-ai-tools.sh --no-gum                  # Skip the gum TUI even in a terminal
#   ./bin/setup-ai-tools.sh --skip-serena             # Do not run Serena
#   ./bin/setup-ai-tools.sh --repo /path/to/repo      # Repeatable; skip inner TUI
# ==============================================================================

set -euo pipefail

# Prefer user-local and Homebrew bins in non-interactive shells (cron, CI, Grok).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

RUN_SERENA=true
RUN_CODEGRAPH=true
RUN_GRAPHIFY=true
FORCE_REBUILD=false
AUTO_INSTALL=true
TARGET_PATH=""
CLI_MODE_FLAGS=false
SKIP_GUM=false
SELECTED_REPOS=()

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --serena-only)
      RUN_SERENA=true
      RUN_CODEGRAPH=false
      RUN_GRAPHIFY=false
      CLI_MODE_FLAGS=true
      shift
      ;;
    --codegraph-only)
      RUN_SERENA=false
      RUN_CODEGRAPH=true
      RUN_GRAPHIFY=false
      CLI_MODE_FLAGS=true
      shift
      ;;
    --graphify-only)
      RUN_SERENA=false
      RUN_CODEGRAPH=false
      RUN_GRAPHIFY=true
      CLI_MODE_FLAGS=true
      shift
      ;;
    --force)
      FORCE_REBUILD=true
      CLI_MODE_FLAGS=true
      shift
      ;;
    --no-install)
      AUTO_INSTALL=false
      CLI_MODE_FLAGS=true
      shift
      ;;
    --no-gum)
      SKIP_GUM=true
      shift
      ;;
    --skip-serena)
      RUN_SERENA=false
      CLI_MODE_FLAGS=true
      shift
      ;;
    --skip-codegraph)
      RUN_CODEGRAPH=false
      CLI_MODE_FLAGS=true
      shift
      ;;
    --skip-graphify)
      RUN_GRAPHIFY=false
      CLI_MODE_FLAGS=true
      shift
      ;;
    --repo)
      if [ -z "${2:-}" ]; then
        echo "Error: --repo needs a path" >&2
        exit 1
      fi
      SELECTED_REPOS+=("${2%/}")
      CLI_MODE_FLAGS=true
      shift 2
      ;;
    -h|--help)
      sed -ne '/^#/!q;s/^# //;2,$p' "$0"
      exit 0
      ;;
    *)
      TARGET_PATH="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers for the tool lib files
LIB="$SCRIPT_DIR/lib"
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/detect-tools.sh
. "$LIB/detect-tools.sh"
# shellcheck source=lib/codegraph.sh
. "$LIB/codegraph.sh"
# shellcheck source=lib/graphify.sh
. "$LIB/graphify.sh"
# shellcheck source=lib/write-mcp.sh
. "$LIB/write-mcp.sh"

# gum TUI when we are on a terminal and the caller did not pass mode flags.
# If gum is missing: install it and stop, or continue with flags/defaults.
want_interactive() {
  [ "$SKIP_GUM" != true ] && [ "$CLI_MODE_FLAGS" != true ] && [ -t 0 ] && [ -t 1 ]
}

install_gum_and_stop() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "[!] Homebrew not found; cannot install gum."
    echo "    Install gum yourself (https://github.com/charmbracelet/gum) and re-run."
    exit 1
  fi
  echo "[*] Installing gum via Homebrew..."
  brew install gum
  echo ""
  echo "[✓] gum installed. Re-run this script for the interactive menu:"
  echo "    $0${TARGET_PATH:+ $TARGET_PATH}"
  exit 0
}

ask_install_gum_or_continue() {
  echo ""
  echo "[!] gum is not installed. The interactive menu needs it."
  echo "    1) Install gum (brew install gum), then stop — re-run for the TUI"
  echo "    2) Continue without gum (use flags / current defaults)"
  local ans=""
  while true; do
    printf "Choose 1 or 2: "
    read -r ans || exit 1
    case "$ans" in
      1) install_gum_and_stop ;;
      2)
        echo "[*] Continuing without gum."
        return 0
        ;;
      *) echo "    Please enter 1 or 2." ;;
    esac
  done
}

is_project_dir() {
  local dir="${1%/}"
  [ -d "$dir/.git" ] || [ -f "$dir/.serena/project.yml" ] || [ -f "$dir/Cargo.toml" ] || [ -f "$dir/Gemfile" ] || [ -f "$dir/package.json" ]
}

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

run_gum_menu() {
  local selected scan_root selected_names name
  local -a repo_names=()

  selected="$(gum choose --no-limit \
    --header "Which tools to set up? (space to toggle, enter to confirm)" \
    Serena CodeGraph Graphify)" || exit 1
  if [ -z "$selected" ]; then
    echo "[!] No tools selected. Exiting."
    exit 1
  fi
  RUN_SERENA=false
  RUN_CODEGRAPH=false
  RUN_GRAPHIFY=false
  case $'\n'"$selected"$'\n' in *$'\n'Serena$'\n'*) RUN_SERENA=true ;; esac
  case $'\n'"$selected"$'\n' in *$'\n'CodeGraph$'\n'*) RUN_CODEGRAPH=true ;; esac
  case $'\n'"$selected"$'\n' in *$'\n'Graphify$'\n'*) RUN_GRAPHIFY=true ;; esac

  if gum confirm --default=false "Force rebuild CodeGraph / Graphify?"; then
    FORCE_REBUILD=true
  else
    FORCE_REBUILD=false
  fi

  if gum confirm --default=true "Install missing tools if they are not on PATH?"; then
    AUTO_INSTALL=true
  else
    AUTO_INSTALL=false
  fi

  scan_root="${TARGET_PATH:-$SCRIPT_DIR}"
  scan_root="${scan_root%/}"

  if is_project_dir "$scan_root"; then
    SELECTED_REPOS=("$scan_root")
    TARGET_PATH="$scan_root"
    return 0
  fi

  while IFS= read -r name; do
    [ -n "$name" ] && repo_names+=("$name")
  done < <(list_child_repo_names "$scan_root")

  if [ "${#repo_names[@]}" -eq 0 ]; then
    echo "[!] No project folders found in $scan_root"
    exit 1
  fi

  selected_names="$(gum choose --no-limit \
    --header "Which repos to configure? (space to toggle, enter to confirm)" \
    "${repo_names[@]}")" || exit 1
  if [ -z "$selected_names" ]; then
    echo "[!] No repos selected. Exiting."
    exit 1
  fi

  SELECTED_REPOS=()
  while IFS= read -r name; do
    [ -n "$name" ] && SELECTED_REPOS+=("$scan_root/$name")
  done <<< "$selected_names"
  TARGET_PATH="$scan_root"
}

if want_interactive; then
  if command -v gum >/dev/null 2>&1; then
    run_gum_menu
  else
    ask_install_gum_or_continue
  fi
fi

TARGET_DIR="${TARGET_PATH:-$SCRIPT_DIR}"

echo "================================================================="
echo " AI Code Intelligence Setup: Serena + CodeGraph + Graphify"
echo " Target Directory: $TARGET_DIR"
if [ "${#SELECTED_REPOS[@]}" -gt 0 ]; then
  echo " Selected Repos:   ${#SELECTED_REPOS[@]}"
  local_repo=""
  for local_repo in "${SELECTED_REPOS[@]}"; do
    echo "   - $(basename "$local_repo")"
  done
fi
echo " Force Rebuild:    $FORCE_REBUILD"
echo " Auto Install:     $AUTO_INSTALL"
echo " DeepSeek Model:   deepseek-v4-pro"
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Binary Detection, Auto-Install, Dependency Verification
# ------------------------------------------------------------------------------
SERENA_BIN=""
CODEGRAPH_BIN=""
GRAPHIFY_BIN=""
GRAPHIFY_MCP_BIN=""
GROK_BIN=""

resolve_tool_bins
ensure_missing_tools
resolve_tool_bins

echo "[✓] Serena:    ${SERENA_BIN:-NOT FOUND}"
echo "[✓] CodeGraph: ${CODEGRAPH_BIN:-NOT FOUND}"
echo "[✓] Graphify:  ${GRAPHIFY_BIN:-NOT FOUND}"
echo "[✓] Graph-MCP: ${GRAPHIFY_MCP_BIN:-NOT FOUND}"
echo "[✓] Grok:      ${GROK_BIN:-NOT FOUND}"

ensure_graphify_mcp_extra "$GRAPHIFY_MCP_BIN" || true

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "[!] Warning: DEEPSEEK_API_KEY is not set in the current environment."
  echo "    Graphify semantic extraction will be skipped unless DEEPSEEK_API_KEY is exported."
fi

# ------------------------------------------------------------------------------
# 2. Update Global Gitignore and AI Client Settings
# ------------------------------------------------------------------------------
setup_global_gitignore
setup_global_mcp

# ------------------------------------------------------------------------------
# 3. Project Processor Function
# ------------------------------------------------------------------------------
process_project() {
  local repo="${1%/}"
  local repo_name="$(basename "$repo")"

  echo ""
  echo "================================================================="
  echo " Processing: $repo_name"
  echo " Path:       $repo"
  echo "================================================================="

  # A. CodeGraph: init only when missing; --force on an existing index is sync
  codegraph_setup "$repo" || true

  # B. Serena Project Initialization
  if [ "$RUN_SERENA" = true ] && [ -n "$SERENA_BIN" ]; then
    if [ ! -f "$repo/.serena/project.yml" ]; then
      echo "[*] [Serena] Creating project configuration..."
      yes n | "$SERENA_BIN" project create "$repo" >/dev/null 2>&1 || true
    else
      echo "[✓] [Serena] Project configuration exists."
    fi
  fi

  # C. Graphify Knowledge Graph Extraction (via DeepSeek deepseek-v4-pro)
  graphify_extract "$repo" || true

  # C2. Graphify should not treat MCP configs this script writes as extract inputs
  ensure_graphify_ignore "$repo"

  # D-G. Write all project-level MCP / rules files
  write_project_mcp "$repo"
}

# ------------------------------------------------------------------------------
# 5. Execution Router (picked repos, single repo, or all children)
# ------------------------------------------------------------------------------
if [ "${#SELECTED_REPOS[@]}" -gt 0 ]; then
  for sub_repo in "${SELECTED_REPOS[@]}"; do
    process_project "$sub_repo"
  done
elif is_project_dir "$TARGET_DIR"; then
  process_project "$TARGET_DIR"
else
  for sub_repo in "$TARGET_DIR"/*/; do
    [ -d "$sub_repo" ] || continue
    sub_repo_name="$(basename "$sub_repo")"

    if [[ "$sub_repo_name" == .* ]]; then
      continue
    fi

    process_project "$sub_repo"
  done
fi

echo ""
echo "================================================================="
echo " [✓] All AI code intelligence tools configured successfully!"
echo "================================================================="
