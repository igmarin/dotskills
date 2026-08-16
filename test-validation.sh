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
echo "=========================================="
echo "Test Results: $pass_count/$test_count passed"
if [ "$fail_count" -gt 0 ]; then
  echo "FAILED: $fail_count test(s) failed"
  exit 1
else
  echo "SUCCESS: All tests passed"
  exit 0
fi
