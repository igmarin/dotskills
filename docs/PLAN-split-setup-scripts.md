# Plan: split `bin/setup-ai-tools.sh` into `bin/lib/`

Decided 2026-08-15.
Do not implement in this session. Use this file as the source of truth. Do not re-litigate it.

Scope: this repo only (`dotskills`). Do not edit `rs-guard`. Do not harvest `~/.agents/skills`. Do not commit unless asked.

---

## What we are doing

`bin/setup-ai-tools.sh` is one long tools pass. The configuration flow is already a single unit: `./bin/dotskills` (one gum session → skills → tools). This plan extracts the tools pass into smaller sourced files so later changes (CodeGraph, Graphify extra, MCP writer) need only one edit.

This is a refactor. Flags, skip/sync rules, and extras stay the same. There is no new product.

### Completed context

- `bin/setup-ai-tools.sh` is already in this repo.
- Graphify extra is `graphifyy[mcp,openai]`.
- CodeGraph rule: missing → `init`; exists → skip; `--force` + exists → `sync`.
- `bin/dotskills` is the one entry point.
- `setup-rs-guard` stays an opt-in extra.

---

## Settled (do not reopen)

1. **One gum TUI.** It lives in `bin/dotskills`. Tools scripts must not add a second menu. `setup-ai-tools.sh` keeps `--no-gum`, `--skip-*`, and `--repo` for the dispatcher.
2. **`bin/dotskills` stays the human entry point.** `./install.sh` stays a shim to `bin/install-skills.sh`. `bin/setup-ai-tools.sh` stays the tools step that `dotskills` calls.
3. **`bin/install-skills.sh` stays one file** unless it grows enough to hurt. Do not split it in this work.
4. **Extract one piece at a time.** Prove it works after each extract. Do not rewrite the whole tools script in one step.
5. **No `SKILL.md` for the installer.** It is still a human/local program.
6. **No machine-absolute paths** in shipped scripts or README (`/Volumes/minimini/...`). Use home-relative (`~/.agents/skills`) and repo-relative (`bin/…`) paths only.
7. **Error handling consistency:**
   - Lib files use `return 1` for errors, not `exit 1`.
   - The main script handles error propagation.
   - All error messages go to stderr.
8. **No duplicated helper code.** All lib files source `bin/lib/common.sh`.
9. Behavior that must not change:
   - Graphify install: `graphifyy[mcp,openai]`
   - CodeGraph: missing → `init`; exists → skip; `--force` + exists → `sync` (not `init`, not `index`)
   - Skills default: three owned repos + generic `skills/`; `setup-rs-guard` only with `--with-rs-guard`
   - Community: `npx skills install -g <slug> --all`, not clone
   - Elixir: `--with=elixir-phoenix-skills` only

---

## Target shape

```
bin/
├── dotskills                 # unchanged job: gum + dispatch
├── install-skills.sh         # unchanged job: owned clones + extras
├── setup-ai-tools.sh         # thin: flags, order of steps, process_project
└── lib/
    ├── common.sh             # shared helpers (log, warn, ok, run, usage header?)
    ├── paths.sh              # already present — script_dir_of
    ├── detect-tools.sh       # resolve PATH + optional install
    ├── codegraph.sh          # init / skip / sync
    ├── graphify.sh           # extra, extract, .graphifyignore
    └── write-mcp.sh          # global + per-repo MCP / gitignore / clinerules
```

`setup-ai-tools.sh` `source`s the lib files. Do not make the lib files independently invokable unless a later extract needs it.

Suggested source pattern from `setup-ai-tools.sh` after `SCRIPT_DIR` is known:

```bash
LIB="$SCRIPT_DIR/lib"
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/paths.sh
. "$LIB/paths.sh"
# shellcheck source=lib/detect-tools.sh
. "$LIB/detect-tools.sh"
```

Lib files source each other (e.g. `write-mcp.sh` → `common.sh`) using the same pattern: resolve `SCRIPT_DIR`/`LIB` from `BASH_SOURCE[0]`.

---

## State contract

Lib files receive state via:
- Global variables set by `setup-ai-tools.sh` (e.g. `VERBOSE`, `DRY_RUN`, `FORCE`)
- Function arguments (e.g. `codegraph_setup "$repo"`)

Lib files must NOT:
- Modify global state without documentation
- Read from stdin unless explicitly documented
- Exit directly (use `return 1` for errors; let the caller handle propagation)
- Call `set -e` themselves

---

## Tasks (order — stop after each proof)

### Task 0. Extract shared utilities

Create `bin/lib/common.sh` with helpers used by multiple tool lib files:
- `log`, `info`, `ok`, `warn`
- `log_cmd`, `run` (respects `DRY_RUN` and `VERBOSE`)
- Optionally `usage()` only if it is shared; otherwise keep it in `setup-ai-tools.sh`.

Replace duplicate helpers in `setup-ai-tools.sh` with sources.

**Done when:**
- `bash -n bin/lib/common.sh` passes
- `bash -n bin/setup-ai-tools.sh` still passes
- `./bin/setup-ai-tools.sh --help` still works
- No duplicate `log/info/ok/warn/run/log_cmd` definitions in `setup-ai-tools.sh`

### Task 1. Extract detect / install

Move these functions into `bin/lib/detect-tools.sh`:
- `resolve_tool_bins`
- `ensure_uv`
- `install_serena`
- `install_graphify`
- `install_codegraph`
- `ensure_missing_tools`

Keep the global `*_BIN` variables in `setup-ai-tools.sh` (lib uses and returns into them).

**Done when:**
- `bash -n` on both files passes
- `./bin/setup-ai-tools.sh --no-gum --no-install .` still prints the same tool-found lines (or `NOT FOUND`)
- Does not re-`init` CodeGraph if `.codegraph` exists

### Task 2. Extract CodeGraph

Move the `process_project` CodeGraph block into `bin/lib/codegraph.sh` as one function, e.g. `codegraph_setup "$repo"`.

- Keep the three-way rule in one place.
- Return status codes: `0` = skipped, `1` = error, maybe `2` = synced (document them in the function comment).

**Done when:**
- `.codegraph` present → no "Initializing" / no `init`
- `--force` with index present → `sync` only
- `./bin/setup-ai-tools.sh --no-gum --no-install .` still behaves the same

### Task 3. Extract Graphify

Move into `bin/lib/graphify.sh`:
- `ensure_graphify_mcp_extra`
- `ensure_graphify_ignore`
- The extract block (consider a separate `graphify_extract "$repo"` function for testability)

Extra stays `graphifyy[mcp,openai]`.

**Done when:**
- Header / install strings still say `[mcp,openai]`
- Extract still skipped when `graph.json` exists and `--force` is off
- `.graphifyignore` still lists generated MCP configs

### Task 4. Extract MCP / gitignore / rules writers

Move into `bin/lib/write-mcp.sh`:
- Global gitignore updates
- Devin / Cline / Grok / Zed global MCP configs
- `upsert_grok_mcp_toml`
- Per-repo JSON/TOML/clinerules writers

If `upsert_grok_mcp_toml` is too complex, consider a separate `bin/lib/grok-mcp.sh` and document the decision.

**Done when:**
- `./bin/setup-ai-tools.sh --no-gum --no-install --skip-serena --skip-codegraph --skip-graphify --repo .` still writes the same config filenames
- Global gitignore contains the same patterns
- No duplicated writer code in `setup-ai-tools.sh`

### Task 5. Thin `setup-ai-tools.sh` + README

`setup-ai-tools.sh` should become:
- Flag parsing
- Setting state variables
- Sourcing lib files
- A short `process_project` loop that calls `codegraph_setup`, `graphify_*`, `write_*`

Update README structure tree to list `bin/lib/`.

Do not change `bin/dotskills` gum copy unless a path broke.

**Done when:**
- `./bin/dotskills --help` still describes one flow
- `./bin/dotskills tools --no-gum --no-install .` still skips CodeGraph init

### Task 6. Cleanup and polish

- Remove dead code
- Remove unused variables
- Consolidate imports in `setup-ai-tools.sh`
- Add `shellcheck source=...` directives above every `.` of a lib file
- Run `grep -n "^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=" bin/setup-ai-tools.sh` and verify every assignment is used

**Done when:**
- `bash -n` passes
- No unused variables
- No orphaned comments
- Whole proof passes

---

## Out of scope

- A second gum TUI
- Splitting `install-skills.sh`
- A `SKILL.md` for `setup-ai-tools`
- Changing default skill sources, npx list, or rs-guard facts
- Running setup against every project
- Mixing a behavior change with an extract

---

## Proof (run after every task)

```bash
set -euo pipefail

for script in bin/dotskills bin/setup-ai-tools.sh bin/install-skills.sh bin/lib/*.sh; do
  bash -n "$script" || { echo "Syntax error in $script"; exit 1; }
done

# lib files must not exit directly or set -e themselves
if grep -r "exit 1" bin/lib/*.sh >/dev/null; then
  echo "Forbidden: lib files contain exit 1 (use return 1 instead)"
  exit 1
fi

if grep -r "set -e" bin/lib/*.sh >/dev/null; then
  echo "Forbidden: lib files set -e themselves (caller sets it)"
  exit 1
fi

# Behavior checks
./bin/dotskills --help
./bin/setup-ai-tools.sh --no-gum --no-install .
# no CodeGraph "Initializing" / init when .codegraph already exists
```

Interactive check (human, next session if a TTY is available): `./bin/dotskills` is still one gum session.

---

## Rollback strategy

After each task, commit with a clear message like `Extract: detect-tools (Task 1)` and ensure the worktree is clean before proceeding.

If the next task breaks behavior:
1. Find the last good task commit (e.g. `git log --oneline --since="20 minutes ago"`)
2. Verify it is the commit you want to keep
3. Run `git reset --hard <that-commit-hash>`

Do not blindly use `HEAD~1` unless you have verified it points to the last good task commit.

---

## Prompt for the next window

Read `docs/PROMPT-split-setup-scripts.md`.
