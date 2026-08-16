# Graphify setup helper.
#
# Usage: . "$LIB/graphify.sh"
#
# Globals this file reads (caller must set):
#   GRAPHIFY_BIN
#   GRAPHIFY_MCP_BIN
#   FORCE_REBUILD
#   DEEPSEEK_API_KEY

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Ensure the graphify-mcp entry point has the mcp and openai extras.
# Re-installs graphifyy[mcp,openai] if either import is missing.
ensure_graphify_mcp_extra() {
  local mcp_bin="$1"
  [ -n "$mcp_bin" ] && [ -e "$mcp_bin" ] || return 0

  local shebang mcp_py
  shebang="$(head -1 "$mcp_bin" 2>/dev/null || true)"
  mcp_py="${shebang#\#!}"
  case "$mcp_py" in
    *[!a-zA-Z0-9/_.@-]*) mcp_py="" ;;
  esac
  if [ -z "$mcp_py" ] || [ ! -x "$mcp_py" ]; then
    if command -v uv >/dev/null 2>&1; then
      mcp_py="$(uv tool run --from graphifyy python -c 'import sys; print(sys.executable)' 2>/dev/null || true)"
    fi
  fi
  [ -n "$mcp_py" ] || return 0

  local mcp_ok=false openai_ok=false
  if "$mcp_py" -c "from mcp.server.stdio import stdio_server" >/dev/null 2>&1; then
    mcp_ok=true
  fi
  if "$mcp_py" -c "import openai" >/dev/null 2>&1; then
    openai_ok=true
  fi
  if [ "$mcp_ok" = true ] && [ "$openai_ok" = true ]; then
    echo "[✓] Graphify MCP + OpenAI extras are installed."
    return 0
  fi

  echo "[*] Graphify extras missing — installing graphifyy[mcp,openai]..."
  if command -v uv >/dev/null 2>&1; then
    uv tool install --force --reinstall "graphifyy[mcp,openai]" || {
      echo "[!] Failed to install graphifyy[mcp,openai] via uv. Graphify MCP / DeepSeek extract will fail."
      return 1
    }
  else
    "$mcp_py" -m pip install -q "graphifyy[mcp,openai]" || {
      echo "[!] Failed to install graphifyy[mcp,openai] via pip. Graphify MCP / DeepSeek extract will fail."
      return 1
    }
  fi

  if [ -x "$HOME/.local/bin/graphify-mcp" ]; then
    GRAPHIFY_MCP_BIN="$HOME/.local/bin/graphify-mcp"
  fi
  if "$mcp_py" -c "from mcp.server.stdio import stdio_server" >/dev/null 2>&1 \
     && "$mcp_py" -c "import openai" >/dev/null 2>&1; then
    echo "[✓] Graphify MCP + OpenAI extras installed."
  else
    echo "[!] graphifyy[mcp,openai] installed but import still fails."
    return 1
  fi
}

# Graphify extract treats generated MCP JSON as "code" (zero nodes).
# .graphifyignore is the documented exclude file.
ensure_graphify_ignore() {
  local repo="$1"
  local ignore="$repo/.graphifyignore"
  touch "$ignore"
  add_if_missing ".cline_mcp_servers.json" "$ignore"
  add_if_missing ".clinerules" "$ignore"
  add_if_missing ".mcp.json" "$ignore"
  add_if_missing ".devin/mcp_config.json" "$ignore"
  add_if_missing ".devin/config.local.json" "$ignore"
  add_if_missing ".zed/settings.json" "$ignore"
  add_if_missing ".grok/config.toml" "$ignore"
  add_if_missing ".cursor/mcp.json" "$ignore"
}

# Extract the Graphify knowledge graph for a repo.
# Returns 0 if completed or skipped, 1 if the extract command failed.
graphify_extract() {
  local repo="${1%/}"

  if [ "$RUN_GRAPHIFY" != true ] || [ -z "$GRAPHIFY_BIN" ]; then
    return 0
  fi

  if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
    echo "[!] [Graphify] Skipped extraction (DEEPSEEK_API_KEY not set)."
    return 0
  fi

  if [ "$FORCE_REBUILD" = true ] || [ ! -f "$repo/graphify-out/graph.json" ]; then
    echo "[*] [Graphify] Extracting knowledge graph via DeepSeek (deepseek-v4-pro)..."
    local extra_flags=""
    if [ -f "$repo/Cargo.toml" ]; then
      extra_flags="--cargo"
    fi
    if "$GRAPHIFY_BIN" extract "$repo" --backend deepseek --model deepseek-v4-pro --no-cluster $extra_flags; then
      return 0
    else
      return 1
    fi
  else
    echo "[✓] [Graphify] graphify-out/graph.json already exists."
    return 0
  fi
}
