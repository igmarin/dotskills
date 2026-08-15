#!/usr/bin/env bash
# Shim — real installer is bin/install-skills.sh
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/install-skills.sh" "$@"
