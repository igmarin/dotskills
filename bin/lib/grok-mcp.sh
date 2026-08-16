# Grok MCP, hooks, and rules helpers.
#
# Usage: . "$LIB/grok-mcp.sh"
#
# Globals this file reads (caller must set):
#   SERENA_BIN
#   CODEGRAPH_BIN
#   GRAPHIFY_MCP_BIN
#   GROK_BIN

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

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

# Project-level Grok MCP + rules.
_write_grok_project() {
  local repo="$1"
  local backend="${2:-deepseek}"
  local model="${3:-deepseek-v4-pro}"
  if [ -n "$GROK_BIN" ]; then
    mkdir -p "$repo/.grok/rules"
    upsert_grok_mcp_toml "$repo/.grok/config.toml" "$repo"
    echo "[✓] [Grok] project MCP written to $repo/.grok/config.toml"
    local file="$repo/.grok/rules/code-intelligence.md"
    cat << 'EOF' > "$file"
# Code intelligence

Use these tools before dumping whole files or grepping the tree.

1. If `.codegraph/` exists, run `codegraph explore "<symbol or question>"` (or the CodeGraph MCP tools).
2. Use Serena MCP tools (`get_symbols_overview`, `find_symbol`, `find_declaration`, `find_referencing_symbols`, `read_memory`) for LSP-level code navigation and project memory when the Serena server is connected.
3. If `graphify-out/graph.json` exists, use Graphify (`graphify query`, `graphify explain`, `graphify path`, or the Graphify MCP). Treat codebase questions as graph queries first.
4. Regenerate Graphify with `graphify extract . --backend {{BACKEND}} --model {{MODEL}} --no-cluster` ({{BACKEND}} `{{MODEL}}` is the chosen model). The backend and model are configurable via `setup-ai-tools.sh --provider` / `--model`. Rust workspaces also pass `--cargo`.
EOF
    sed -e "s|{{BACKEND}}|${backend}|g" -e "s|{{MODEL}}|${model}|g" "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  fi
}
