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

# Merge [mcp_servers.<name>] tables into a Grok config.toml without clobbering
# other sections ([cli], [models], [ui], ...). Used for both ~/.grok/config.toml
# and per-project .grok/config.toml.
upsert_grok_mcp_toml() {
  local config_path="$1"
  local repo_path="${2:-}"
  python3 - "$config_path" "$repo_path" \
    "${CODEGRAPH_BIN:-}" "${GRAPHIFY_MCP_BIN:-}" "${SERENA_BIN:-}" << 'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
repo = sys.argv[2].rstrip("/")
codegraph, graphify_mcp, serena = sys.argv[3:6]

servers = []
if codegraph:
    args = ["serve", "--mcp"]
    if repo:
        args += ["--path", repo]
    servers.append(("codegraph", {
        "command": codegraph,
        "args": args,
        "enabled": True,
    }))
if graphify_mcp:
    graph = f"{repo}/graphify-out/graph.json" if repo else "graphify-out/graph.json"
    servers.append(("graphify", {
        "command": graphify_mcp,
        "args": ["--graph", graph],
        "enabled": True,
        "startup_timeout_sec": 30,
    }))
if serena:
    servers.append(("serena", {
        "command": serena,
        "args": ["start-mcp-server", "--context=claude-code", "--project-from-cwd"],
        "enabled": True,
    }))


def fmt_str(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fmt_table(name: str, spec: dict) -> str:
    lines = [f"[mcp_servers.{name}]"]
    lines.append(f"command = {fmt_str(spec['command'])}")
    args = ", ".join(fmt_str(a) for a in spec["args"])
    lines.append(f"args = [{args}]")
    if spec.get("enabled", True):
        lines.append("enabled = true")
    if "startup_timeout_sec" in spec:
        lines.append(f"startup_timeout_sec = {spec['startup_timeout_sec']}")
    return "\n".join(lines) + "\n"


path.parent.mkdir(parents=True, exist_ok=True)
text = path.read_text(encoding="utf-8") if path.exists() else ""

for name, spec in servers:
    block = fmt_table(name, spec)
    pattern = re.compile(
        rf"(?ms)^\[mcp_servers\.{re.escape(name)}\][^\n]*\n(?:(?!^\[).*\n?)*"
    )
    if pattern.search(text):
        text = pattern.sub(lambda _m, b=block: b + "\n", text, count=1)
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        if text and not text.endswith("\n\n"):
            text += "\n"
        text += block + "\n"

path.write_text(text, encoding="utf-8")
PY
}

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
# 2. Update Global Gitignore (~/.gitignore_global)
# ------------------------------------------------------------------------------
# Preserve user's existing gitignore if they have one configured
GITIGNORE_GLOBAL="$(git config --global core.excludesfile 2>/dev/null || echo "$HOME/.gitignore_global")"
touch "$GITIGNORE_GLOBAL"
git config --global core.excludesfile "$GITIGNORE_GLOBAL"

# Drop already-tracked MCP configs from the git index so the global
# excludesfile actually hides them. Does not delete the working copies.
untrack_mcp_configs() {
  local repo="$1"
  [ -d "$repo/.git" ] || return 0
  local f
  for f in \
    .mcp.json \
    .cline_mcp_servers.json \
    .clinerules \
    .cursor/mcp.json \
    .devin/mcp_config.json \
    .devin/config.local.json \
    .zed/settings.json \
    .grok/config.toml
  do
    if git -C "$repo" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git -C "$repo" rm --cached -q --ignore-unmatch "$f" || true
      echo "[*] [git] untracked $f (globally ignored; working copy kept)"
    fi
  done
}

echo "[*] Ensuring global gitignore ($GITIGNORE_GLOBAL)..."
add_if_missing "# Local artifacts & system" "$GITIGNORE_GLOBAL"
add_if_missing ".DS_Store" "$GITIGNORE_GLOBAL"
add_if_missing "review-result.txt" "$GITIGNORE_GLOBAL"
add_if_missing "rs-guard-metrics.json" "$GITIGNORE_GLOBAL"
add_if_missing ".rs-guard/cache/" "$GITIGNORE_GLOBAL"
add_if_missing "" "$GITIGNORE_GLOBAL"
add_if_missing "# AI code intelligence & tooling" "$GITIGNORE_GLOBAL"
add_if_missing ".codegraph/" "$GITIGNORE_GLOBAL"
add_if_missing "graphify-out/" "$GITIGNORE_GLOBAL"
add_if_missing ".serena/" "$GITIGNORE_GLOBAL"
add_if_missing ".grok/" "$GITIGNORE_GLOBAL"
add_if_missing ".kiro/" "$GITIGNORE_GLOBAL"
add_if_missing ".aider" "$GITIGNORE_GLOBAL"
add_if_missing ".aider.chat.history.md" "$GITIGNORE_GLOBAL"
add_if_missing ".aider.input.history" "$GITIGNORE_GLOBAL"
add_if_missing ".aider.tags.cache.v4/" "$GITIGNORE_GLOBAL"
add_if_missing "" "$GITIGNORE_GLOBAL"
add_if_missing "" "$GITIGNORE_GLOBAL"
add_if_missing "# MCP config files (machine-local paths; do not commit)" "$GITIGNORE_GLOBAL"
add_if_missing ".mcp.json" "$GITIGNORE_GLOBAL"
add_if_missing ".cursor/mcp.json" "$GITIGNORE_GLOBAL"
add_if_missing "" "$GITIGNORE_GLOBAL"
add_if_missing "# Cline" "$GITIGNORE_GLOBAL"
add_if_missing ".cline_mcp_servers.json" "$GITIGNORE_GLOBAL"
add_if_missing ".clinerules" "$GITIGNORE_GLOBAL"
add_if_missing "" "$GITIGNORE_GLOBAL"
add_if_missing "# Devin" "$GITIGNORE_GLOBAL"
add_if_missing ".devin/" "$GITIGNORE_GLOBAL"
add_if_missing ".devin/config.local.json" "$GITIGNORE_GLOBAL"
add_if_missing ".devin/*.local.json" "$GITIGNORE_GLOBAL"
add_if_missing ".devin/mcp_config.json" "$GITIGNORE_GLOBAL"
add_if_missing "" "$GITIGNORE_GLOBAL"
add_if_missing "# Zed" "$GITIGNORE_GLOBAL"
add_if_missing ".zed/" "$GITIGNORE_GLOBAL"
add_if_missing ".zed/settings.json" "$GITIGNORE_GLOBAL"

# ------------------------------------------------------------------------------
# 3. Global AI Client Setup (Devin, Cline, Grok, Zed)
# ------------------------------------------------------------------------------
echo "[*] Configuring global client settings..."

# --- Devin Global Setup ---
mkdir -p "$HOME/.config/devin/skills/serena"
python3 -c "
import json, os
mcp_path = os.path.expanduser('~/.config/devin/mcp_config.json')
data = {'mcpServers': {}}
if os.path.exists(mcp_path):
    try:
        with open(mcp_path, 'r') as f:
            data = json.load(f)
    except Exception:
        pass
if 'mcpServers' not in data:
    data['mcpServers'] = {}

if '$SERENA_BIN':
    data['mcpServers']['serena'] = {
        'command': '$SERENA_BIN',
        'args': ['start-mcp-server', '--context=claude-code', '--project-from-cwd']
    }
with open(mcp_path, 'w') as f:
    json.dump(data, f, indent=2)

cfg_path = os.path.expanduser('~/.config/devin/config.json')
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, 'r') as f:
            data = json.load(f)
        perms = data.setdefault('permissions', {}).setdefault('allow', [])
        for p in ['mcp__serena__*', 'mcp__codegraph__*', 'mcp__graphify__*']:
            if p not in perms:
                perms.append(p)
        with open(cfg_path, 'w') as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass
"

# Devin Serena Skill
cat << 'EOF' > "$HOME/.config/devin/skills/serena/SKILL.md"
---
name: serena
description: "Semantic and symbolic code intelligence powered by Serena (LSP backend). Use for precise AST/symbol exploration, finding declarations, references, implementations, symbol overviews, compiler diagnostics, and persistent project memories."
argument-hint: "[symbol|file|query|memory]"
triggers:
  - user
  - model
---

# Serena Code Intelligence

Serena connects language servers (Rust Analyzer, Solargraph, TypeScript, Pyright, Go gopls, etc.) via Model Context Protocol (MCP) to provide AST-level semantic understanding, symbol references, compiler diagnostics, and persistent project memories.

## Available Serena MCP Tools

Access Serena tools using `mcp_call_tool` with `server_name: "serena"`.

### 1. Symbolic Navigation & Code Understanding
- `get_symbols_overview`: Lists all top-level symbols (functions, structs, traits, classes, methods) in a file.
- `find_symbol`: Performs global or local symbol lookup by name, prefix, or qualified path.
- `find_declaration`: Locates the exact definition/declaration of a symbol.
- `find_implementations`: Finds symbols that implement a given interface, trait, or abstract class.
- `find_referencing_symbols`: Finds all call sites and references across the codebase.
- `get_diagnostics_for_file`: Fetches LSP compiler errors, warnings, and lints for a given file.

### 2. AST-Aware Refactoring & Edits
- `replace_symbol_body`: Replaces the full definition of a symbol cleanly at the AST level.
- `insert_after_symbol` / `insert_before_symbol`: Inserts code before or after a specific symbol definition.
- `rename_symbol`: Renames a symbol across all referencing files.
- `safe_delete_symbol`: Safely deletes an unused symbol.

### 3. Project Memories & Onboarding
- `list_memories`: Lists stored markdown memories in `.serena/memories/`.
- `read_memory`: Reads a project memory file containing architecture notes or guidelines.
- `write_memory`: Records durable project knowledge for future agent sessions.
- `edit_memory`: Edits an existing memory.
- `onboarding`: Gathers high-level project architecture and conventions.
EOF

# --- Cline Global Setup ---
mkdir -p "$HOME/.cline/data/settings" "$HOME/.cline/rules"
mkdir -p "$HOME/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings"

cat << 'EOF' > "$HOME/.cline/rules/serena.md"
<!-- serena-rules -->
## Serena Code Intelligence & Memory

When Serena MCP tools (`mcp__serena__*` or `serena_*`) are available, use them for AST-aware symbolic navigation and persistent memories:

1. **Symbolic Discovery & Exploration**:
   - `get_symbols_overview(relative_path)`: Inspect top-level structs, functions, classes, and methods instead of reading entire files.
   - `find_symbol(name_path_pattern)`: Global symbol search across the codebase.
   - `find_declaration(name_path_pattern, relative_path)`: Jump directly to symbol definition.
   - `find_implementations(name_path_pattern, relative_path)`: Find trait/interface implementations.
   - `find_referencing_symbols(name_path_pattern, relative_path)`: Find all callers and usages before refactoring.

2. **Diagnostics & Quality**:
   - `get_diagnostics_for_file(relative_path)`: Verify LSP diagnostics and compiler errors.

3. **Precise Refactoring**:
   - `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol`, `rename_symbol`: AST-level symbol replacements without syntax or indentation breaks.

4. **Project Memories**:
   - `list_memories()` / `read_memory(memory_name)`: Check `.serena/memories/` for stored architectural patterns and guidelines.
   - `write_memory(memory_name, content)`: Persist key project conventions and takeaways.
<!-- /serena-rules -->
EOF

CLINE_AUTO_APPROVE='["get_symbols_overview", "find_symbol", "find_declaration", "find_implementations", "find_referencing_symbols", "get_diagnostics_for_file", "list_memories", "read_memory", "write_memory", "edit_memory", "onboarding"]'

update_cline_mcp_json() {
  local target="$1"
  python3 -c "
import json, os
path = os.path.expanduser('$target')
if not os.path.exists(os.path.dirname(path)):
    os.makedirs(os.path.dirname(path), exist_ok=True)
data = {'mcpServers': {}}
if os.path.exists(path):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except Exception:
        pass
if 'mcpServers' not in data:
    data['mcpServers'] = {}

if '$SERENA_BIN':
    data['mcpServers']['serena'] = {
        'command': '$SERENA_BIN',
        'args': ['start-mcp-server', '--context=claude-code', '--project-from-cwd'],
        'disabled': False,
        'autoApprove': $CLINE_AUTO_APPROVE
    }
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
}

update_cline_mcp_json "$HOME/.cline/data/settings/cline_mcp_settings.json"
update_cline_mcp_json "$HOME/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
if [ -d "$HOME/Library/Application Support/Devin/User/globalStorage/saoudrizwan.claude-dev/settings" ]; then
  update_cline_mcp_json "$HOME/Library/Application Support/Devin/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
fi

# --- Grok Global Setup ---
# Other clients get JSON MCP configs. Grok reads TOML from
# ~/.grok/config.toml (user) and <repo>/.grok/config.toml (project).
# The old path only wrote Serena hooks, so Graphify/CodeGraph never
# started in Grok even when they worked in Cline/Devin/Zed.
if [ -n "$GROK_BIN" ]; then
  if [ -n "$SERENA_BIN" ]; then
    "$SERENA_BIN" setup grok 2>/dev/null || true
  fi
  mkdir -p "$HOME/.grok/hooks" "$HOME/.grok/rules"
  upsert_grok_mcp_toml "$HOME/.grok/config.toml" ""
  echo "[✓] Grok user MCP servers written to ~/.grok/config.toml"

  if [ -n "$GRAPHIFY_BIN" ]; then
    # Refresh the user-level agents skill (Grok scans ~/.agents/skills/).
    "$GRAPHIFY_BIN" install --platform agents >/dev/null 2>&1 || true
  fi

  cat << 'EOF' > "$HOME/.grok/hooks/serena-hooks.json"
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "grep|read_file|run_terminal_command",
        "hooks": [
          {
            "type": "command",
            "command": "serena-hooks remind --client=grok",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "serena-hooks cleanup --client=grok",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF
else
  echo "[!] Grok CLI not found; skipped ~/.grok/config.toml MCP wiring."
fi

# --- Zed Global Setup ---
ZED_SETTINGS="$HOME/.config/zed/settings.json"
if [ -f "$ZED_SETTINGS" ]; then
  python3 -c "
import json, os
path = os.path.expanduser('$ZED_SETTINGS')
try:
    with open(path, 'r') as f:
        data = json.load(f)
    cs = data.setdefault('context_servers', {})
    if '$SERENA_BIN':
        cs['serena'] = {
            'command': '$SERENA_BIN',
            'args': ['start-mcp-server', '--context=ide', '--project-from-cwd']
        }
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
except Exception:
    pass
"
fi

# ------------------------------------------------------------------------------
# 4. Project Processor Function
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

  # D. Update Project-Level .cline_mcp_servers.json
  CLINE_PROJ_JSON="$repo/.cline_mcp_servers.json"
  python3 -c "
import json, os
path = '$CLINE_PROJ_JSON'
data = {'mcpServers': {}}
if os.path.exists(path):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except Exception:
        pass
if 'mcpServers' not in data:
    data['mcpServers'] = {}

if '$CODEGRAPH_BIN':
    data['mcpServers']['codegraph'] = {
        'command': '$CODEGRAPH_BIN',
        'args': ['serve', '--mcp', '--path', '$repo']
    }
if '$GRAPHIFY_MCP_BIN':
    data['mcpServers']['graphify'] = {
        'command': '$GRAPHIFY_MCP_BIN',
        'args': ['--graph', '$repo/graphify-out/graph.json']
    }
if '$SERENA_BIN':
    data['mcpServers']['serena'] = {
        'command': '$SERENA_BIN',
        'args': ['start-mcp-server', '--context=claude-code', '--project-from-cwd']
    }
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"

  # E. Update Project-Level .devin/mcp_config.json
  mkdir -p "$repo/.devin"
  DEVIN_PROJ_JSON="$repo/.devin/mcp_config.json"
  python3 -c "
import json, os
path = '$DEVIN_PROJ_JSON'
data = {'mcpServers': {}}
if os.path.exists(path):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except Exception:
        pass
if 'mcpServers' not in data:
    data['mcpServers'] = {}

if '$CODEGRAPH_BIN':
    data['mcpServers']['codegraph'] = {
        'command': '$CODEGRAPH_BIN',
        'args': ['serve', '--mcp', '--path', '$repo']
    }
if '$GRAPHIFY_MCP_BIN':
    data['mcpServers']['graphify'] = {
        'command': '$GRAPHIFY_MCP_BIN',
        'args': ['--graph', '$repo/graphify-out/graph.json']
    }
if '$SERENA_BIN':
    data['mcpServers']['serena'] = {
        'command': '$SERENA_BIN',
        'args': ['start-mcp-server', '--context=claude-code', '--project-from-cwd']
    }
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"

  # F. Update Project-Level .zed/settings.json
  mkdir -p "$repo/.zed"
  ZED_PROJ_JSON="$repo/.zed/settings.json"
  python3 -c "
import json, os
path = '$ZED_PROJ_JSON'
data = {'context_servers': {}}
if os.path.exists(path):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except Exception:
        pass
if 'context_servers' not in data:
    data['context_servers'] = {}

if '$CODEGRAPH_BIN':
    data['context_servers']['codegraph'] = {
        'command': '$CODEGRAPH_BIN',
        'args': ['serve', '--mcp']
    }
if '$GRAPHIFY_MCP_BIN':
    data['context_servers']['graphify'] = {
        'command': '$GRAPHIFY_MCP_BIN',
        'args': ['--graph', '$repo/graphify-out/graph.json']
    }
if '$SERENA_BIN':
    data['context_servers']['serena'] = {
        'command': '$SERENA_BIN',
        'args': ['start-mcp-server', '--context=ide', '--project-from-cwd']
    }
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"

  # G. Update or Create .clinerules
  CLINERULES_FILE="$repo/.clinerules"
  cat << 'EOF' > "$CLINERULES_FILE"
## Code intelligence

Use these tools before dumping whole files or grepping the tree.

1. If `.codegraph/` exists, run `codegraph explore "<symbol or question>"` (or the CodeGraph MCP tools).
2. Use Serena MCP tools (`get_symbols_overview`, `find_symbol`, `find_declaration`, `find_referencing_symbols`, `read_memory`) for LSP-level code navigation and project memory.
3. If `graphify-out/graph.json` exists, use Graphify (`graphify explain`, `graphify path`, or the Graphify MCP).
4. Regenerate Graphify with `graphify extract . --backend deepseek --model deepseek-v4-pro --no-cluster` (DeepSeek is the global LLM). Rust workspaces also pass `--cargo`.
EOF

  # H. Grok project MCP + rules (Grok does not read .cline_mcp_servers.json)
  if [ -n "$GROK_BIN" ]; then
    mkdir -p "$repo/.grok/rules"
    upsert_grok_mcp_toml "$repo/.grok/config.toml" "$repo"
    echo "[✓] [Grok] project MCP written to $repo/.grok/config.toml"
    cat << 'EOF' > "$repo/.grok/rules/code-intelligence.md"
# Code intelligence

Use these tools before dumping whole files or grepping the tree.

1. If `.codegraph/` exists, run `codegraph explore "<symbol or question>"` (or the CodeGraph MCP tools).
2. Use Serena MCP tools (`get_symbols_overview`, `find_symbol`, `find_declaration`, `find_referencing_symbols`, `read_memory`) for LSP-level code navigation and project memory when the Serena server is connected.
3. If `graphify-out/graph.json` exists, use Graphify (`graphify query`, `graphify explain`, `graphify path`, or the Graphify MCP). Treat codebase questions as graph queries first.
4. Regenerate Graphify with `graphify extract . --backend deepseek --model deepseek-v4-pro --no-cluster` (DeepSeek is the global LLM). Rust workspaces also pass `--cargo`.
EOF
  fi

  untrack_mcp_configs "$repo"
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
