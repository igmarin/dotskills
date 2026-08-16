#!/usr/bin/env bash
# Test suite for validation functions in bin/install-skills.sh
#
# Tests:
#   - valid_slug(): Validates GitHub slug format (owner/repo)
#   - assert_under_sources(): Ensures paths stay within SOURCES_DIR
#
# Usage: bash test-validation.sh
# Requirements: bash 4+, standard Unix utilities
#
# Coverage:
#   - Path traversal attempts (..)
#   - Invalid characters and formats
#   - Symlink attack prevention
#   - Boundary conditions

set -euo pipefail

# Source shared helpers from the actual codebase. valid_slug now lives in
# bin/lib/common.sh; we keep assert_under_sources inline because it is a
# path-safety test harness.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib/paths.sh
. "$SCRIPT_DIR/bin/lib/paths.sh"
# shellcheck source=bin/lib/common.sh
. "$SCRIPT_DIR/bin/lib/common.sh"

# assert_under_sources is tested inline so it can use temp SOURCES_DIR
assert_under_sources() {
  local slug_or_path="$1"
  local sources_resolved
  local target

  # Resolve SOURCES_DIR to its real physical location to prevent symlink attacks
  sources_resolved="$(cd "$SOURCES_DIR" 2>/dev/null && pwd -P)" || {
    echo "Error: cannot resolve SOURCES_DIR: $SOURCES_DIR" >&2
    exit 1
  }

  # If the argument is an existing path, resolve its physical location;
  # otherwise construct the path from the validated slug.
  if [ -e "$slug_or_path" ]; then
    target="$(cd "$slug_or_path" 2>/dev/null && pwd -P)" || {
      echo "Error: cannot resolve path: $slug_or_path" >&2
      exit 1
    }
  else
    target="${sources_resolved}/${slug_or_path}"
  fi

  if [[ "$target" != "$sources_resolved"/* ]]; then
    echo "Error: refusing path outside $SOURCES_DIR: $slug_or_path (resolved to $target)" >&2
    exit 1
  fi
}

# Override config variables for testing
SOURCES_DIR="$(mktemp -d)"
OTHER_PATH="$(mktemp -d)"

# Ensure cleanup on exit
trap 'rm -rf "$SOURCES_DIR" "$OTHER_PATH"' EXIT

test_count=0
pass_count=0
fail_count=0

echo "Testing valid_slug function..."
echo ""

# Should pass
echo "Test 1: valid slug: owner/repo"
if valid_slug "owner/repo"; then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 2: valid slug: owner-name/repo-name"
if valid_slug "owner-name/repo-name"; then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 3: valid slug: owner.repo/repo.repo"
if valid_slug "owner.repo/repo.repo"; then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 4: valid slug: single-letter/r"
if valid_slug "a/b"; then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

# Should fail
echo "Test 5: invalid slug: ../evil"
if valid_slug "../evil"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 6: invalid slug: owner/.."
if valid_slug "owner/.."; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 7: invalid slug: .owner/repo"
if valid_slug ".owner/repo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 8: invalid slug: owner/.repo"
if valid_slug "owner/.repo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 9: invalid slug: owner/./repo"
if valid_slug "owner/./repo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 10: invalid slug: owner/../repo"
if valid_slug "owner/../repo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 11: invalid slug: no separator"
if valid_slug "ownerrepo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 12: invalid slug: empty"
if valid_slug ""; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 13: invalid slug: owner."
if valid_slug "owner."; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 14: invalid slug: -owner/repo"
if valid_slug "-owner/repo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 15: invalid slug: owner-/repo"
if valid_slug "owner-/repo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 16: invalid slug: owner/-repo"
if valid_slug "owner/-repo"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 17: invalid slug: owner/repo-"
if valid_slug "owner/repo-"; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo ""
echo "Testing assert_under_sources function..."
echo ""

# Create a valid path under SOURCES_DIR
mkdir -p "$SOURCES_DIR/owner/repo"

# Test by calling directly and checking exit status
echo "Test 18: valid slug under SOURCES_DIR"
if (assert_under_sources "owner/repo"); then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 19: existing path under SOURCES_DIR"
if (assert_under_sources "$SOURCES_DIR/owner/repo"); then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 20: path outside SOURCES_DIR"
if (assert_under_sources "$OTHER_PATH") 2>/dev/null; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

# Create a symlink attack inside SOURCES_DIR
SYMLINK_NAME="evil-link"
ln -sfn "$OTHER_PATH" "$SOURCES_DIR/$SYMLINK_NAME"

echo "Test 21: symlink attack inside SOURCES_DIR"
if (assert_under_sources "$SOURCES_DIR/$SYMLINK_NAME") 2>/dev/null; then
  echo "  FAIL (should have rejected symlink escape)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected symlink escape)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo ""
echo "Testing bin/dotskills all --dry-run side effects..."
echo ""

# Test: bin/dotskills all --dry-run must not write any files.
# This relies on dry-run staying network-free (no git fetch, gh, or ls-remote).
test_count=$((test_count + 1))
echo "Test 22: dry-run all produces no side effects"
DRY_TMP="$(mktemp -d)"
DRY_HOME="$DRY_TMP/home"
DRY_REPO="$DRY_TMP/repo"
mkdir -p "$DRY_HOME" "$DRY_REPO"
# Initialize a git repo so is_project_dir returns true and the tool loop is exercised.
( cd "$DRY_REPO" && git init -q )
if (
  export HOME="$DRY_HOME"
  # Restrict PATH so grok/serena/codegraph/graphify do not start servers during the test.
  export PATH="/usr/bin:/bin"
  if "$SCRIPT_DIR/bin/dotskills" all --dry-run --no-install --skip-serena --skip-codegraph --skip-graphify --repo owner/test-repo "$DRY_REPO" >/dev/null 2>&1; then
    # After a dry run, no files should be written to $HOME or the target repo.
    HOME_FILES="$(find "$DRY_HOME" -type f 2>/dev/null)"
    REPO_FILES="$(find "$DRY_REPO" -type f -not -path "$DRY_REPO/.git/*" 2>/dev/null)"
    if [ -z "$HOME_FILES" ] && [ -z "$REPO_FILES" ]; then
      exit 0
    else
      echo "  Side effects found: home files: $HOME_FILES; repo files: $REPO_FILES" >&2
      exit 1
    fi
  else
    exit 1
  fi
); then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
rm -rf "$DRY_TMP"

echo ""
echo "Testing setup-ai-tools child project detection..."
echo ""

# Test: setup-ai-tools.sh should only process child directories that look like projects.
test_count=$((test_count + 1))
echo "Test 23: setup-ai-tools only processes project-like children"
CHILD_TMP="$(mktemp -d)"
mkdir -p "$CHILD_TMP/real-project"
mkdir -p "$CHILD_TMP/lib"
( cd "$CHILD_TMP/real-project" && git init -q )

if (
  export HOME="$CHILD_TMP/home"
  export PATH="/usr/bin:/bin"
  mkdir -p "$CHILD_TMP/home"
  "$SCRIPT_DIR/bin/setup-ai-tools.sh" --dry-run --no-install --no-gum --skip-serena --skip-codegraph --skip-graphify "$CHILD_TMP" 2>&1 | tee "$CHILD_TMP/output.txt" >/dev/null
  if grep -q "Would process: real-project" "$CHILD_TMP/output.txt" && ! grep -q "Would process: lib" "$CHILD_TMP/output.txt"; then
    exit 0
  else
    echo "  Output did not match. real-project: $(grep -c "Would process: real-project" "$CHILD_TMP/output.txt"); lib: $(grep -c "Would process: lib" "$CHILD_TMP/output.txt")" >&2
    exit 1
  fi
); then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
rm -rf "$CHILD_TMP"

echo ""
echo "Testing generated rules reflect provider/model..."
echo ""

# Test: generated .grok/rules/code-intelligence.md and .clinerules include the chosen provider/model.
test_count=$((test_count + 1))
echo "Test 24: generated rules use configured provider and model"
RULES_TMP="$(mktemp -d)"
mkdir -p "$RULES_TMP/repo"
mkdir -p "$RULES_TMP/home/bin"
( cd "$RULES_TMP/repo" && git init -q )

# Provide lightweight fake tool binaries so the setup runs without starting servers.
cat > "$RULES_TMP/home/bin/serena" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$RULES_TMP/home/bin/serena"

cat > "$RULES_TMP/home/bin/codegraph" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$RULES_TMP/home/bin/codegraph"

cat > "$RULES_TMP/home/bin/graphify" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$RULES_TMP/home/bin/graphify"

cat > "$RULES_TMP/home/bin/graphify-mcp" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$RULES_TMP/home/bin/graphify-mcp"

cat > "$RULES_TMP/home/bin/grok" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$RULES_TMP/home/bin/grok"

if (
  export HOME="$RULES_TMP/home"
  export PATH="$RULES_TMP/home/bin:/usr/bin:/bin"
  "$SCRIPT_DIR/bin/setup-ai-tools.sh" --no-install --no-gum --skip-serena --skip-codegraph --skip-graphify --provider openai --model gpt-4o "$RULES_TMP/repo" >/dev/null 2>&1
  if [ -f "$RULES_TMP/repo/.grok/rules/code-intelligence.md" ] \
     && grep -q "openai" "$RULES_TMP/repo/.grok/rules/code-intelligence.md" \
     && grep -q "gpt-4o" "$RULES_TMP/repo/.grok/rules/code-intelligence.md" \
     && [ -f "$RULES_TMP/repo/.clinerules" ] \
     && grep -q "openai" "$RULES_TMP/repo/.clinerules" \
     && grep -q "gpt-4o" "$RULES_TMP/repo/.clinerules"; then
    exit 0
  else
    echo "  Generated rules did not contain openai / gpt-4o" >&2
    exit 1
  fi
); then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
rm -rf "$RULES_TMP"

echo ""
echo "Testing dotskills.toml config loading..."
echo ""

# Test: bin/lib/config.sh loads repo config and lets user config override.
test_count=$((test_count + 1))
echo "Test 25: dotskills.toml loads and user override wins"
CONFIG_TMP="$(mktemp -d)"
mkdir -p "$CONFIG_TMP/home/.dotskills"
cat > "$CONFIG_TMP/dotskills.toml" <<'EOF'
[repos]
owned = [
  "owner/repo-a|https://github.com/owner/repo-a.git|skills",
]

[npx]
community = [
  "owner/repo-a",
]
EOF
cat > "$CONFIG_TMP/home/.dotskills/config.toml" <<'EOF'
[npx]
community = [
  "owner/repo-b",
]
EOF

if (
  export HOME="$CONFIG_TMP/home"
  . "$SCRIPT_DIR/bin/lib/config.sh"
  load_dotskills_config "$CONFIG_TMP"
  if [ "${#OWNED_REPOS[@]}" -eq 1 ] \
     && [ "${OWNED_REPOS[0]}" = "owner/repo-a|https://github.com/owner/repo-a.git|skills" ] \
     && [ "${#NPX_COMMUNITY[@]}" -eq 1 ] \
     && [ "${NPX_COMMUNITY[0]}" = "owner/repo-b" ]; then
    exit 0
  else
    echo "  OWNED_REPOS=${OWNED_REPOS[*]}; NPX_COMMUNITY=${NPX_COMMUNITY[*]}" >&2
    exit 1
  fi
); then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
rm -rf "$CONFIG_TMP"

echo ""
echo "Testing setup-ai-tools flag parsing..."
echo ""

# Test: setup-ai-tools.sh rejects --npx because it is a skill-install flag.
test_count=$((test_count + 1))
echo "Test 26: setup-ai-tools.sh rejects --npx"
NPX_TMP="$(mktemp -d)"
mkdir -p "$NPX_TMP/repo"
( cd "$NPX_TMP/repo" && git init -q )
if (
  "$SCRIPT_DIR/bin/setup-ai-tools.sh" --no-install --no-gum --skip-serena --skip-codegraph --skip-graphify --npx owner/repo "$NPX_TMP/repo" >/dev/null 2>&1
); then
  echo "  FAIL (should have exited with an error)" >&2
  fail_count=$((fail_count + 1))
else
  echo "  PASS"
  pass_count=$((pass_count + 1))
fi
rm -rf "$NPX_TMP"

echo ""
echo "Testing config loader fallback..."
echo ""

# Test: load_dotskills_config handles a malformed dotskills.toml gracefully.
test_count=$((test_count + 1))
echo "Test 27: malformed dotskills.toml falls back without crashing"
MALFORMED_TMP="$(mktemp -d)"
echo 'this is not [ valid toml' > "$MALFORMED_TMP/dotskills.toml"
if (
  . "$SCRIPT_DIR/bin/lib/config.sh"
  load_dotskills_config "$MALFORMED_TMP"
  if [ "${#OWNED_REPOS[@]}" -eq 0 ] && [ "${#NPX_COMMUNITY[@]}" -eq 0 ]; then
    exit 0
  else
    echo "  OWNED_REPOS=${OWNED_REPOS[*]}; NPX_COMMUNITY=${NPX_COMMUNITY[*]}" >&2
    exit 1
  fi
); then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
rm -rf "$MALFORMED_TMP"

echo ""
echo "=========================================="
echo "Test Results: $pass_count/$test_count passed"
if [ "$fail_count" -gt 0 ]; then
  echo "FAILED: $fail_count test(s) failed"
  exit 1
else
  echo "SUCCESS: All tests passed"
  exit 0
fi
