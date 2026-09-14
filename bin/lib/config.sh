# shellcheck shell=bash
# dotskills configuration loader.
#
# Usage: . "$LIB/config.sh"
#
# Loads repo-level dotskills.toml and merges it with ~/.dotskills/config.toml.
# User config values override repo config values for the same key.
#
# This function is safe for `set -e` callers: it never exits and always
# returns 0. On any failure (missing python3, missing TOML parser, malformed
# file) it falls back to empty arrays and lets callers use their defaults.
# Python diagnostics are not suppressed, so a missing interpreter or broken
# TOML file is still visible to the user.

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Load dotskills configuration from the repo root and the user home directory.
# $1 = repo root directory (where dotskills.toml is expected)
# Sets: OWNED_REPOS, NPX_COMMUNITY
load_dotskills_config() {
  local repo_root="${1:-.}"
  local repo_config="$repo_root/dotskills.toml"
  local user_config="$HOME/.dotskills/config.toml"

  # Reset arrays so callers can safely append afterwards.
  OWNED_REPOS=()
  NPX_COMMUNITY=()

  local raw
  if ! raw=$(PYTHONDONTWRITEBYTECODE=1 python3 - "$repo_config" "$user_config" <<'PY'
import os
import sys

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None


def fallback_toml(text):
    """Read the two string-array settings dotskills supports on Python < 3.11."""
    result, section, key, values = {}, None, None, []
    saw_content = False
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        saw_content = True
        if line.startswith("[") and line.endswith("]"):
            section, key, values = line[1:-1].strip(), None, []
            continue
        if "=" in line and key is None:
            candidate, value = (part.strip() for part in line.split("=", 1))
            if value.startswith("["):
                key = candidate
                values = [v.strip().strip('"') for v in value[1:].split("]", 1)[0].split(",") if v.strip()]
                if "]" in value:
                    result.setdefault(section, {})[key] = values
                    key = None
            continue
        if key:
            done = "]" in line
            values.extend(v.strip().strip('"') for v in line.split("]", 1)[0].split(",") if v.strip())
            if done:
                result.setdefault(section, {})[key] = values
                key = None
            continue
        raise ValueError("unsupported TOML syntax")
    if key:
        raise ValueError("unterminated array")
    if saw_content and not result:
        raise ValueError("unsupported TOML syntax")
    return result


def load(path):
    try:
        with open(path, "rb") as f:
            if tomllib:
                return tomllib.load(f)
            return fallback_toml(f.read().decode("utf-8"))
    except FileNotFoundError:
        # Optional file is missing. Ignore silently.
        return {}
    except Exception as e:
        # Single-line, safe for the | delimiter the shell expects.
        msg = str(e).replace("\n", " ").replace("|", "/")
        print(f"warn|could not load {path}: {msg}")
        return {}


def get_array(data, *keys):
    for k in keys:
        if not isinstance(data, dict):
            return []
        data = data.get(k, {})
    return data if isinstance(data, list) else []


repo_path, user_path = sys.argv[1:3]
repo = load(repo_path)
user = load(user_path)

# User arrays override repo arrays; repo arrays are the fallback.
owned = get_array(user, "repos", "owned") or get_array(repo, "repos", "owned")
npx = get_array(user, "npx", "community") or get_array(repo, "npx", "community")

for v in owned:
    print(f"owned|{v}")
for v in npx:
    print(f"npx|{v}")
PY
); then
    # Missing python3 or unexpected crash: fall back.
    raw=""
  fi

  local line kind value
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind="${line%%|*}"
    value="${line#*|}"
    case "$kind" in
      owned) OWNED_REPOS+=("$value") ;;
      npx)   NPX_COMMUNITY+=("$value") ;;
      warn)  echo "Warning: $value" >&2 ;;
    esac
  done <<< "$raw"

  return 0
}
