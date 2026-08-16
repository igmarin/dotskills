# Tool detection and installation helpers.
#
# Usage: . "$LIB/detect-tools.sh"
#
# Globals this file reads or writes (caller must set or accept):
#   AUTO_INSTALL  (read by ensure_missing_tools)
#   *_BIN         (written by resolve_tool_bins)
#
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Print the first executable argument, or return 1 if none found.
first_existing() {
  local candidate
  for candidate in "$@"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Resolve tool binaries into the *_BIN globals.
# Writes: SERENA_BIN, CODEGRAPH_BIN, GRAPHIFY_BIN, GRAPHIFY_MCP_BIN, GROK_BIN
resolve_tool_bins() {
  SERENA_BIN="$(first_existing \
    "$(command -v serena 2>/dev/null || true)" \
    "$HOME/.local/bin/serena" \
    || true)"

  CODEGRAPH_BIN="$(first_existing \
    "$(command -v codegraph 2>/dev/null || true)" \
    "$HOME/.local/bin/codegraph" \
    "$HOME/.local/share/mise/installs/node/lts/bin/codegraph" \
    || true)"

  GRAPHIFY_BIN="$(first_existing \
    "$(command -v graphify 2>/dev/null || true)" \
    "$HOME/.local/bin/graphify" \
    || true)"

  GRAPHIFY_MCP_BIN="$(first_existing \
    "$(command -v graphify-mcp 2>/dev/null || true)" \
    "$HOME/.local/bin/graphify-mcp" \
    || true)"

  GROK_BIN="$(first_existing \
    "$(command -v grok 2>/dev/null || true)" \
    "$HOME/.local/bin/grok" \
    || true)"
}

# Ensure uv is installed and on PATH.
ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return 0
  fi
  if [ -x "$HOME/.local/bin/uv" ]; then
    export PATH="$HOME/.local/bin:$PATH"
    return 0
  fi
  echo "[*] uv not found — installing (needed for Serena / Graphify)..."
  if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
    echo "[!] Failed to install uv."
    return 1
  fi
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1
}

install_serena() {
  echo "[*] Installing Serena (uv tool: serena-agent)..."
  ensure_uv || return 1
  if uv tool install -p 3.13 serena-agent || uv tool install serena-agent; then
    hash -r 2>/dev/null || true
    resolve_tool_bins
    if [ -n "$SERENA_BIN" ]; then
      echo "[✓] Serena installed: $SERENA_BIN"
      return 0
    fi
  fi
  echo "[!] Serena install finished but 'serena' is not on PATH."
  return 1
}

install_graphify() {
  echo "[*] Installing Graphify with MCP + OpenAI extras (uv tool: graphifyy[mcp,openai])..."
  ensure_uv || return 1
  if uv tool install --force --reinstall "graphifyy[mcp,openai]"; then
    hash -r 2>/dev/null || true
    resolve_tool_bins
    if [ -n "$GRAPHIFY_BIN" ] && [ -n "$GRAPHIFY_MCP_BIN" ]; then
      echo "[✓] Graphify installed: $GRAPHIFY_BIN"
      return 0
    fi
  fi
  echo "[!] Graphify install finished but graphify / graphify-mcp is not on PATH."
  return 1
}

install_codegraph() {
  echo "[*] Installing CodeGraph (npm: @colbymchenry/codegraph)..."
  local npm_bin=""
  npm_bin="$(command -v npm 2>/dev/null || true)"
  if [ -z "$npm_bin" ]; then
    echo "[!] npm not found. Install Node.js (or mise node) then re-run."
    return 1
  fi
  if "$npm_bin" install -g @colbymchenry/codegraph; then
    hash -r 2>/dev/null || true
    resolve_tool_bins
    if [ -n "$CODEGRAPH_BIN" ]; then
      echo "[✓] CodeGraph installed: $CODEGRAPH_BIN"
      return 0
    fi
  fi
  echo "[!] CodeGraph install finished but 'codegraph' is not on PATH."
  return 1
}

# Install missing tools if AUTO_INSTALL is true.
# Relies on *_BIN globals set by resolve_tool_bins.
ensure_missing_tools() {
  if [ "$AUTO_INSTALL" != true ]; then
    echo "[*] Auto-install disabled (--no-install)."
    return 0
  fi
  [ -z "$SERENA_BIN" ] && install_serena || true
  if [ -z "$GRAPHIFY_BIN" ] || [ -z "$GRAPHIFY_MCP_BIN" ]; then
    install_graphify || true
  fi
  [ -z "$CODEGRAPH_BIN" ] && install_codegraph || true
}
