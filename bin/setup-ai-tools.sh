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
#
# This is a flag-driven script. Use ./bin/dotskills for the interactive gum menu.
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
#   ./bin/setup-ai-tools.sh --skip-serena             # Do not run Serena
#   ./bin/setup-ai-tools.sh --repo /path/to/repo      # Repeatable; target repo
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
SELECTED_REPOS=()

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --serena-only)
      RUN_SERENA=true
      RUN_CODEGRAPH=false
      RUN_GRAPHIFY=false
      shift
      ;;
    --codegraph-only)
      RUN_SERENA=false
      RUN_CODEGRAPH=true
      RUN_GRAPHIFY=false
      shift
      ;;
    --graphify-only)
      RUN_SERENA=false
      RUN_CODEGRAPH=false
      RUN_GRAPHIFY=true
      shift
      ;;
    --force)
      FORCE_REBUILD=true
      shift
      ;;
    --no-install)
      AUTO_INSTALL=false
      shift
      ;;
    --skip-serena)
      RUN_SERENA=false
      shift
      ;;
    --skip-codegraph)
      RUN_CODEGRAPH=false
      shift
      ;;
    --skip-graphify)
      RUN_GRAPHIFY=false
      shift
      ;;
    --repo)
      if [ -z "${2:-}" ]; then
        echo "Error: --repo needs a path" >&2
        exit 1
      fi
      SELECTED_REPOS+=("${2%/}")
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
