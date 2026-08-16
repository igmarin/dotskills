# Plan: split setup-ai-tools.sh (later)

Decided 2026-08-15, after the move/refresh and the unified `bin/dotskills` gum flow.
**Do not implement in the same session as this plan.** Next window: this file is the source of truth. Do not re-litigate it.

Workspace: this repo only (`dotskills`). Do not edit `rs-guard`. Do not harvest `~/.agents/skills`. Do not commit unless asked.

---

## What we are doing

`bin/setup-ai-tools.sh` is one long tools pass. The **configuration flow** is already one unit: `./bin/dotskills` (one gum session → skills → tools). This plan only **extracts** that tools pass into smaller sourced files so a later change (CodeGraph, Graphify extra, MCP writer) is a one-place edit.

This is a refactor. Same flags, same skip/sync rules, same extras. No new product.

---

## Settled (do not reopen)

1. **One gum TUI.** It lives in `bin/dotskills`. Tools scripts must not grow a second menu. `setup-ai-tools.sh` keeps `--no-gum` / `--skip-*` / `--repo` for the dispatcher.
2. **`bin/dotskills` stays the human entry.** `./install.sh` stays a shim to `bin/install-skills.sh`. `bin/setup-ai-tools.sh` stays the tools step `dotskills` calls.
3. **`bin/install-skills.sh` stays one file** unless it has grown enough to hurt. Do not split it in this work.
4. **One extract at a time.** Prove after each extract. Do not rewrite the whole tools script in one step.
5. **No `SKILL.md` for the installer.** Still a human/local program.
6. **No machine-absolute paths** in shipped scripts or README (`/Volumes/minimini/...`). Home-relative (`~/.agents/skills`) and repo-relative (`bin/…`) only.
7. **Error handling consistency:**
   - Lib files use `return 1` for errors, not `exit 1`
   - Main script handles error propagation
   - All error messages go to stderr
8. Behavior that must not change:
   - Graphify install: `graphifyy[mcp,openai]`
   - CodeGraph: missing → `init`; exists → skip; `--force` + exists → `sync` (not `init`, not `index`)
   - Skills default: three owned repos + generic `skills/`; `setup-rs-guard` only with `--with-rs-guard`
   - Community: npx `skills install -g <slug> --all`, not clone
   - Elixir: `--with=elixir-phoenix-skills` only

---

## Target shape

```
bin/
├── dotskills                 # unchanged job: gum + dispatch
├── install-skills.sh         # unchanged job: owned clones + extras
├── setup-ai-tools.sh         # thin: flags, order of steps, process_project
└── lib/
    ├── common.sh             # shared helpers (log, warn, ok, run)
    ├── paths.sh              # already present — script_dir_of
    ├── detect-tools.sh       # resolve PATH + optional install
    ├── codegraph.sh          # init / skip / sync
    ├── graphify.sh           # extra, extract, .graphifyignore
    └── write-mcp.sh          # global + per-repo MCP / gitignore / clinerules
```

`setup-ai-tools.sh` `source`s the lib files. Do not make the lib files independently invokable unless a later extract needs it.

Suggested `source` from `setup-ai-tools.sh` after `ROOT`/`SCRIPT_DIR` is known:

```bash
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
# shellcheck source=lib/detect-tools.sh
. "$LIB/detect-tools.sh"
```

## State contract

Lib files receive state via:
- Global variables set by setup-ai-tools.sh (e.g., VERBOSE, DRY_RUN, FORCE)
- Function arguments (e.g., codegraph_setup "$repo")

Lib files must NOT:
- Modify global state without documentation
- Read from stdin unless explicitly documented
- Exit directly (use `return 1` for errors, let caller handle propagation)

---

## Tasks (order — stop after each proof)

### 0. Extract shared utilities

Move any helper functions used by multiple tools (e.g., log, warn, ok, run) into `bin/lib/common.sh`.

**Done when:** No duplicate helper functions remain in the final lib files; `bash -n bin/lib/common.sh` passes.

### 1. Extract detect / install

Move `resolve_tool_bins`, `ensure_uv`, `install_serena`, `install_graphify`, `install_codegraph`, `ensure_missing_tools` into `bin/lib/detect-tools.sh`.

**Done when:** `bash -n` on the two files; `./bin/setup-ai-tools.sh --no-gum --no-install .` still prints the same tool-found lines (or `NOT FOUND`) and does not re-`init` CodeGraph if `.codegraph` exists.

### 2. Extract CodeGraph

Move the `process_project` CodeGraph block into `bin/lib/codegraph.sh` (one function, e.g. `codegraph_setup "$repo"`). Keep the three-way rule in one place. The function should return a status code for "skipped" vs "synced" vs "error" if needed for later use.

**Done when:** `.codegraph` present → no "Initializing" / no `init`. `--force` with index present → `sync` only.

### 3. Extract Graphify

Move `ensure_graphify_mcp_extra`, `ensure_graphify_ignore`, and the extract block into `bin/lib/graphify.sh`. Extra stays `graphifyy[mcp,openai]`. Consider making the extract block a separate function for testability.

**Done when:** header / install strings still say `[mcp,openai]`; extract still skipped when `graph.json` exists and `--force` is off; `.graphifyignore` still lists generated MCP configs.

### 4. Extract MCP / gitignore writers

Move global gitignore, Devin / Cline / Grok / Zed global setup, `upsert_grok_mcp_toml`, and the per-repo JSON/TOML/clinerules writers into `bin/lib/write-mcp.sh`. Consider extracting `upsert_grok_mcp_toml` into its own file if it's complex.

**Done when:** `./bin/setup-ai-tools.sh --no-gum --no-install --skip-serena --skip-codegraph --skip-graphify --repo .` still writes the same config filenames (do not re-run a full multi-repo pass).

### 5. Thin `setup-ai-tools.sh` + README

`setup-ai-tools.sh` should be flags + call order + `process_project` as a short loop. Update the README structure tree to list `bin/lib/`. Do not change `bin/dotskills` gum copy unless a path broke.

**Done when:** `./bin/dotskills --help` still describes one flow; `./bin/dotskills tools --no-gum --no-install .` still skips CodeGraph init.

### 6. Cleanup and polish

Remove dead code, unused variables, and consolidate imports in setup-ai-tools.sh.

**Done when:** `bash -n` passes; no unused variables; grep shows no orphaned comments.

---

## Out of scope

- A second gum TUI
- Splitting `install-skills.sh`
- A `SKILL.md` for setup-ai-tools
- Changing default skill sources, npx list, or rs-guard facts
- Running setup against every project
- Mixing a behavior change with an extract

---

## Proof (whole plan)

```bash
bash -n bin/dotskills bin/setup-ai-tools.sh bin/install-skills.sh bin/lib/*.sh
./bin/dotskills tools --no-gum --no-install .
# no CodeGraph "Initializing" / init when .codegraph exists
./bin/dotskills --help

# Additional verification
grep -r "exit 1" bin/lib/*.sh  # Should be empty (use return instead)
grep -r "set -e" bin/lib/*.sh   # Should be empty (caller sets it)
bash -n bin/lib/*.sh           # Syntax check all lib files
```

Interactive check (human, next session if a TTY is available): `./bin/dotskills` is still **one** gum session.

## Rollback strategy

After each task, commit with message like "Extract: detect-tools (Task 1)".
If the next task breaks behavior, use `git reset --hard HEAD~1` to revert.

---

## Prompt for the next window

Read `docs/PROMPT-split-setup-scripts.md`.
