#!/usr/bin/env bash
# Run all validation steps for the dotskills repo.
#
# Usage: ./bin/run-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fail=0

# 1. Syntax check every shell script.
echo "[*] Checking bash syntax..."
for script in \
  "$ROOT/bin/dotskills" \
  "$ROOT/bin/install-skills.sh" \
  "$ROOT/bin/setup-ai-tools.sh" \
  "$ROOT/bin/lib/"*.sh \
  "$ROOT/bin/run-tests.sh" \
  "$ROOT/install.sh" \
  "$ROOT/test-validation.sh"
do
  if ! bash -n "$script"; then
    echo "[✗] Syntax error in $script" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "[✓] Bash syntax OK"

# 2. Run the validation suite.
echo "[*] Running test-validation.sh..."
if bash "$ROOT/test-validation.sh"; then
  echo "[✓] test-validation.sh passed"
else
  fail=1
fi

# 3. Run shellcheck if it is installed.
if command -v shellcheck >/dev/null 2>&1; then
  echo "[*] Running shellcheck..."
  if shellcheck \
    "$ROOT/bin/dotskills" \
    "$ROOT/bin/install-skills.sh" \
    "$ROOT/bin/setup-ai-tools.sh" \
    "$ROOT/bin/lib/"*.sh \
    "$ROOT/install.sh" \
    "$ROOT/test-validation.sh"; then
    echo "[✓] shellcheck passed"
  else
    fail=1
  fi
else
  echo "[!] shellcheck not installed; skipping static analysis."
  echo "    Install it to catch quoting, expansion, and portability issues."
fi

if [ "$fail" -eq 0 ]; then
  echo ""
  echo "[✓] All checks passed."
  exit 0
else
  echo ""
  echo "[✗] Some checks failed."
  exit 1
fi
