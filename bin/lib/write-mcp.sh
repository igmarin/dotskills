# MCP, gitignore, and AI client configuration helpers.
#
# Usage: . "$LIB/write-mcp.sh"
#
# Globals this file reads (caller must set or the function computes):
#   SERENA_BIN, CODEGRAPH_BIN, GRAPHIFY_MCP_BIN, GROK_BIN
#   GITIGNORE_GLOBAL (computed by setup_global_gitignore)

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Append patterns to the global gitignore and ensure git uses it.
setup_global_gitignore() {
  GITIGNORE_GLOBAL="$(git config --global core.excludesfile 2>/dev/null || echo "$HOME/.gitignore_global")"
  export GITIGNORE_GLOBAL
  touch "$GITIGNORE_GLOBAL"
  git config --global core.excludesfile "$GITIGNORE_GLOBAL"

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
}

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

# Configure Devin global MCP and permissions.
_setup_devin_global() {
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
}

# Update a Cline MCP settings JSON file.
_update_cline_mcp_json() {
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

# Configure Cline global MCP and rules.
_setup_cline_global() {
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

  _update_cline_mcp_json "$HOME/.cline/data/settings/cline_mcp_settings.json"
  _update_cline_mcp_json "$HOME/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
  if [ -d "$HOME/Library/Application Support/Devin/User/globalStorage/saoudrizwan.claude-dev/settings" ]; then
    _update_cline_mcp_json "$HOME/Library/Application Support/Devin/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
  fi
}

# Configure Grok global MCP, hooks, and rules.
_setup_grok_global() {
  if [ -n "$GROK_BIN" ]; then
    if [ -n "$SERENA_BIN" ]; then
      "$SERENA_BIN" setup grok 2>/dev/null || true
    fi
    mkdir -p "$HOME/.grok/hooks" "$HOME/.grok/rules"
    upsert_grok_mcp_toml "$HOME/.grok/config.toml" ""
    echo "[✓] Grok user MCP servers written to ~/.grok/config.toml"

    if [ -n "$GRAPHIFY_BIN" ]; then
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
}

# Configure Zed global context servers.
_setup_zed_global() {
  local zed_settings="$HOME/.config/zed/settings.json"
  if [ -f "$zed_settings" ]; then
    python3 -c "
import json, os
path = os.path.expanduser('$zed_settings')
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
}

# Configure all global AI clients (Devin, Cline, Grok, Zed).
setup_global_mcp() {
  echo "[*] Configuring global client settings..."
  _setup_devin_global
  _setup_cline_global
  _setup_grok_global
  _setup_zed_global
}

# Project-level Cline MCP config.
_write_cline_mcp_json() {
  local repo="$1"
  local cline_proj_json="$repo/.cline_mcp_servers.json"
  python3 -c "
import json, os
path = '$cline_proj_json'
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
}

# Project-level Devin MCP config.
_write_devin_mcp_json() {
  local repo="$1"
  local devin_proj_json="$repo/.devin/mcp_config.json"
  mkdir -p "$repo/.devin"
  python3 -c "
import json, os
path = '$devin_proj_json'
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
}

# Project-level Zed settings.
_write_zed_settings() {
  local repo="$1"
  local zed_proj_json="$repo/.zed/settings.json"
  mkdir -p "$repo/.zed"
  python3 -c "
import json, os
path = '$zed_proj_json'
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
}

# Project-level .clinerules.
_write_clinerules() {
  local repo="$1"
  cat << 'EOF' > "$repo/.clinerules"
## Code intelligence

Use these tools before dumping whole files or grepping the tree.

1. If `.codegraph/` exists, run `codegraph explore "<symbol or question>"` (or the CodeGraph MCP tools).
2. Use Serena MCP tools (`get_symbols_overview`, `find_symbol`, `find_declaration`, `find_referencing_symbols`, `read_memory`) for LSP-level code navigation and project memory.
3. If `graphify-out/graph.json` exists, use Graphify (`graphify explain`, `graphify path`, or the Graphify MCP).
4. Regenerate Graphify with `graphify extract . --backend deepseek --model deepseek-v4-pro --no-cluster` (DeepSeek is the global LLM). Rust workspaces also pass `--cargo`.
EOF
}

# Project-level Grok MCP + rules.
_write_grok_project() {
  local repo="$1"
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
}

# Write all project-level MCP / rules files for a repo.
write_project_mcp() {
  local repo="${1%/}"
  _write_cline_mcp_json "$repo"
  _write_devin_mcp_json "$repo"
  _write_zed_settings "$repo"
  _write_clinerules "$repo"
  _write_grok_project "$repo"
  untrack_mcp_configs "$repo"
}
