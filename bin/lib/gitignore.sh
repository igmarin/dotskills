# Global gitignore and MCP config untracking helpers.
#
# Usage: . "$LIB/gitignore.sh"
#
# Globals this file reads or writes (caller must set or the function computes):
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
