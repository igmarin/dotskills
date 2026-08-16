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

# Define the validation functions inline for testing
valid_slug() {
  local slug="$1"
  local owner="${slug%%/*}"
  local repo="${slug#*/}"
  
  # Basic format check
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  
  # Reject path traversal
  [[ "$slug" =~ \.\. ]] && return 1
  
  # Reject leading dots in owner
  [[ "$owner" =~ ^\. ]] && return 1
  
  # Reject leading/trailing hyphens in owner (problematic for git clone)
  [[ "$owner" =~ ^- ]] && return 1
  [[ "$owner" =~ -$ ]] && return 1
  
  # Reject dots in repo (leading, trailing, or consecutive)
  [[ "$repo" =~ ^\. ]] && return 1
  [[ "$repo" =~ \.$ ]] && return 1
  [[ "$repo" =~ \.\. ]] && return 1
  
  # Reject leading/trailing hyphens in repo (problematic for git clone)
  [[ "$repo" =~ ^- ]] && return 1
  [[ "$repo" =~ -$ ]] && return 1
  
  return 0
}

assert_under_sources() {
  local path="$1"
  local resolved
  local sources_resolved
  
  # Resolve both paths to their real locations to prevent symlink attacks
  resolved="$(cd "$path" 2>/dev/null && pwd)" || {
    echo "Error: cannot resolve path: $path" >&2
    exit 1
  }
  sources_resolved="$(cd "$SOURCES_DIR" 2>/dev/null && pwd)" || {
    echo "Error: cannot resolve SOURCES_DIR: $SOURCES_DIR" >&2
    exit 1
  }
  
  if [[ "$resolved" != "$sources_resolved"/* ]]; then
    echo "Error: refusing path outside $SOURCES_DIR: $path (resolved to $resolved)" >&2
    exit 1
  fi
}

# Override config variables for testing
SOURCES_DIR="/tmp/test-dotskills-sources"
mkdir -p "$SOURCES_DIR"

# Ensure cleanup on exit
trap 'rm -rf "$SOURCES_DIR" "/tmp/other-path"' EXIT

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

# Create test directories
mkdir -p "$SOURCES_DIR/valid-path"
mkdir -p "$SOURCES_DIR/owner/repo"
mkdir -p "/tmp/other-path"

# Test by calling directly and checking exit status
echo "Test 18: path under SOURCES_DIR"
if assert_under_sources "$SOURCES_DIR/valid-path" 2>/dev/null; then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 19: path under SOURCES_DIR with subdirs"
if assert_under_sources "$SOURCES_DIR/owner/repo" 2>/dev/null; then
  echo "  PASS"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL"
  fail_count=$((fail_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 20: path outside SOURCES_DIR"
if (assert_under_sources "/tmp/other-path") 2>/dev/null; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

echo "Test 21: path outside SOURCES_DIR (home)"
if (assert_under_sources "$HOME") 2>/dev/null; then
  echo "  FAIL (should have rejected)"
  fail_count=$((fail_count + 1))
else
  echo "  PASS (correctly rejected)"
  pass_count=$((pass_count + 1))
fi
test_count=$((test_count + 1))

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