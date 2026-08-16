#!/usr/bin/env bash
# Shim — real installer is bin/install-skills.sh
set -euo pipefail

# shellcheck source=bin/lib/paths.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/lib/paths.sh"
exec "$(script_dir_of "${BASH_SOURCE[0]}")/bin/install-skills.sh" "$@"
