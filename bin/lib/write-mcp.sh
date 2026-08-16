# MCP, gitignore, and AI client configuration orchestrator.
#
# Usage: . "$LIB/write-mcp.sh"
#
# Globals this file reads (caller must set):
#   SERENA_BIN, CODEGRAPH_BIN, GRAPHIFY_BIN, GRAPHIFY_MCP_BIN, GROK_BIN

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# shellcheck source=lib/gitignore.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gitignore.sh"
# shellcheck source=lib/grok-mcp.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/grok-mcp.sh"

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
4. Regenerate Graphify with `graphify extract . --backend deepseek --model deepseek-v4-pro --no-cluster` (DeepSeek `deepseek-v4-pro` is the default model). The backend and model are configurable via `setup-ai-tools.sh --provider` / `--model`. Rust workspaces also pass `--cargo`.
EOF
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
