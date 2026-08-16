# Prompt — split `bin/setup-ai-tools.sh` into `bin/lib/`

Start this in a new session whose cwd is the dotskills repository root.

---

Read `docs/PLAN-split-setup-scripts.md`. That file is the source of truth. Do not re-litigate it.

Work only in `/Volumes/minimini/Developer/Projects/dotskills`. Do not edit `rs-guard`. Do not harvest `~/.agents/skills`.

## Do

Implement the plan **one task at a time**, in this order, stopping to run the proof after each task:

0. **Extract shared utilities** into `bin/lib/common.sh`
1. **Extract detect / install** into `bin/lib/detect-tools.sh`
2. **Extract CodeGraph** into `bin/lib/codegraph.sh`
3. **Extract Graphify** into `bin/lib/graphify.sh`
4. **Extract MCP / gitignore / rules writers** into `bin/lib/write-mcp.sh` (and `bin/lib/grok-mcp.sh` only if `upsert_grok_mcp_toml` is too large)
5. **Thin `setup-ai-tools.sh`** and update `README.md` structure tree
6. **Cleanup and polish**

Rules for the refactor:
- Lib files use `return 1`, not `exit 1`
- Lib files do NOT call `set -e`
- `setup-ai-tools.sh` is thin: flags, state, source libs, `process_project` loop
- Same behavior: same flags, same skip/sync rules, same MCP configs, same gitignore patterns
- No machine-absolute paths in shipped scripts or README
- One gum TUI stays in `bin/dotskills` only

## Do not

- Add a second gum TUI
- Split `bin/install-skills.sh`
- Create a `SKILL.md` for `setup-ai-tools.sh`
- Change default skill sources, npx list, or rs-guard facts
- Run a full multi-repo setup pass unless you need one repo to verify CodeGraph skip/`sync`
- Commit unless I ask

## Proof (after every task)

```bash
set -euo pipefail

for script in bin/dotskills bin/setup-ai-tools.sh bin/install-skills.sh bin/lib/*.sh; do
  bash -n "$script" || { echo "Syntax error in $script"; exit 1; }
done

if grep -r "exit 1" bin/lib/*.sh >/dev/null; then
  echo "Forbidden: lib files contain exit 1 (use return 1 instead)"
  exit 1
fi

if grep -r "set -e" bin/lib/*.sh >/dev/null; then
  echo "Forbidden: lib files set -e themselves (caller sets it)"
  exit 1
fi

./bin/dotskills --help
./bin/setup-ai-tools.sh --no-gum --no-install .
# no CodeGraph "Initializing" / init when .codegraph already exists
```

If a task breaks the proof, fix it before moving to the next task.
