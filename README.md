# dotskills

My personal agent skill ecosystem — one installer for skills I author, plus a local script for Serena / CodeGraph / Graphify.

## What this is

Agent skills are structured instruction files (`SKILL.md`) that teach AI coding agents how to do specific things: write a PRD, run a TDD loop, set up rs-guard, review code. They live in `~/.agents/skills/` and are loaded on demand by agents like Claude Code, Devin, and others.

This repo does three things:

1. **Holds my personal skills** — skills that are specific to my setup. These live in `skills/` here. `setup-rs-guard` is optional and is **not** copied on a default `./install.sh`.
2. **Installs skills I author** — `bin/install-skills.sh` (root `./install.sh` is a shim) clones my repos and copies their `skills/` trees into `~/.agents/skills/`.
3. **Houses `bin/setup-ai-tools.sh`** — a local (human) installer for Serena, CodeGraph, and Graphify. Not a skill.

One configuration flow: `./bin/dotskills`. In a terminal that is **one gum menu** (skills extras + tools + repos), then skills run, then tools. Commands (`skills` / `tools` / `all`) are for scripts and CI.

## Why public

Skills are configuration for AI agents, not secrets. Sharing them openly means:

- Others can see the patterns and adapt them
- The install approach is reproducible on any machine
- It's a useful reference for anyone building their own skill ecosystem

The default install must work for a fork that never uses rs-guard or Elixir.

## Why "personal"

The skills in `skills/` here are **opinionated to my specific setup**. For example, `setup-rs-guard` references my GitHub username, my repo names, and the mistakes I made the first time. These are not general-purpose skills — they're a personal runbook.

If you find them useful, fork this repo and replace the personal references with your own.

## `./install.sh` vs npx

**Clone with `./install.sh`** only for skills you author. It copies trees into `~/.agents/skills/` and will overwrite a same-named skill that npx already put there.

**Install third-party and published collections with npx**, not a git clone. `npx skills install -g <slug> --all` pulls the whole collection and updates it the same way later. Cloning those repos here fights npx and goes stale.

This machine's `~/.agents/skills/` mix is not a source of truth and is not harvested into this repo.

## Skill sources

### `./install.sh` and `./bin/dotskills` (clone)

Interactive (`./bin/dotskills` or `./bin/dotskills skills` in a terminal):
- Uses `gh repo list --limit 50` to show your most recently updated GitHub repos
- Multi-select with `gum`, or add a custom `owner/repo-name` not in the list
- Requires `gh` installed and authenticated (`gh auth login`)

Non-interactive / script:
```bash
./bin/dotskills skills --repo owner/repo-name --repo owner/another-repo
./bin/dotskills skills --npx owainlewis/blueprint --npx owner/another-collection
./install.sh --repo owner/repo-name --repo owner/another-repo
./install.sh --npx owner/another-collection
```

| Priority | Source | When |
|----------|--------|------|
| 1 (highest) | `dotskills/skills/` (this repo) | Always (generic personal). **`setup-rs-guard` only with `--with-rs-guard`.** |
| 2 | Default owned repos | Non-interactive, no `--repo` |
| 2 | Repos selected from `gh` / `--repo` | Interactive or explicit `--repo` |
| 2 | [`igmarin/elixir-phoenix-skills`](https://github.com/igmarin/elixir-phoenix-skills) | `--with=elixir-phoenix-skills` (work-only) |

**Collision policy:** later copies win. Personal skills override everything.

### npx (collections — not cloned)

Pass `--all` because these are collections. The `bin/dotskills` TUI shows the recommended list pre-selected and lets you add custom `owner/repo` slugs; non-interactively use `--npx owner/repo`.

```bash
npx skills install -g igmarin/agnostic-planning-skills --all
npx skills install -g igmarin/ruby-core-skills --all
npx skills install -g igmarin/rails-agent-skills --all
npx skills install -g owainlewis/agent-skills --all
npx skills install -g owainlewis/blueprint --all
npx skills install -g mattpocock/skills --all
npx skills install -g dietrichgebert/ponytail --all
```

`./install.sh --npx owner/repo` npx-installs that collection. It does **not** clone it. The recommended collections are pre-selected in the TUI.

### Optional extras (off by default)

| Flag | What it adds |
|------|-------------|
| `--npx owner/repo` | npx-install the recommended collections above, or any custom collection |
| `--with=elixir-phoenix-skills` | Clone [`igmarin/elixir-phoenix-skills`](https://github.com/igmarin/elixir-phoenix-skills) — work machine only |
| `--with-rs-guard` | Copy `skills/setup-rs-guard` (personal AI-review runbook; not for every fork) |

## Personal skills

| Skill | What it does |
|-------|-------------|
| [`setup-rs-guard`](skills/setup-rs-guard/SKILL.md) *(optional)* | Runbook for adding rs-guard **v1.7.0** / **`deepseek-v4-pro`** to a repo. Install only with `./install.sh --with-rs-guard`. |

## Install

```bash
git clone https://github.com/igmarin/dotskills.git
cd dotskills
./bin/dotskills              # gum: pick skill repos from gh + npx collections + tools + repos
./install.sh                 # skills only: default owned repos (shim)
./bin/dotskills all --no-gum --no-install .
```

`./bin/dotskills` with no command, in a terminal, is the same unit: one gum session, then skills, then tools. The skills step uses `gh repo list` if `gh` is installed and authenticated; otherwise it falls back to the default owned repos.  
`./bin/dotskills skills [flags]` → `bin/install-skills.sh`  
`./bin/dotskills tools [flags]` → `bin/setup-ai-tools.sh`  
`./bin/dotskills all [tools flags]` → skills (defaults), then tools. `--dry-run` on `all` is passed to skills and **not** to tools (tools would interpret `--dry-run` as a project path argument). Skill flags include `--repo` and `--npx`; tool flags include `--provider` and `--model` for graphify.

This will:

1. Create `~/.dotskills/sources/` and clone the selected source repos there
2. Copy those skills into `~/.agents/skills/`
3. Copy generic personal skills last (they always win). `setup-rs-guard` is not copied unless you pass `--with-rs-guard`

To update later:

```bash
./install.sh
```

Re-running is safe — it pulls the latest from each source and re-copies. It does **not** delete skills that left the list (old google/cloudflare copies stay until you `./install.sh --clean`).

### Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would happen without making changes |
| `--verbose` | Log each command as it executes |
| `--only=slug1,slug2` | Install only specified sources (comma-separated). Generic personal skills still copy; `setup-rs-guard` stays gated |
| `--repo owner/repo` | Clone an additional owned repo (repeatable). Overrides the default list. |
| `--npx owner/repo` | npx-install a skill collection (repeatable). Pre-selected in the TUI. |
| `--with=elixir-phoenix-skills` | Also install elixir-phoenix-skills (work-only) |
| `--with-rs-guard` | Also copy `skills/setup-rs-guard` |
| `--uninstall` / `--clean` | Remove all installed skills from `~/.agents/skills/` |
| `--help` | Show usage information |

### Dry run

```bash
./install.sh --dry-run
```

Shows exactly what would be installed without making any changes.

### Verbose mode

```bash
./install.sh --verbose
```

Logs each command being executed for debugging or transparency.

### Selective install

```bash
./install.sh --only=igmarin/rails-agent-skills,igmarin/ruby-core-skills
```

Installs only the specified sources. Generic personal skills from this repo are still copied. `setup-rs-guard` is still skipped unless `--with-rs-guard`.

### Uninstall

```bash
./install.sh --uninstall
```

Removes all skills from `~/.agents/skills/` with a confirmation prompt.

## Local tool setup (`bin/setup-ai-tools.sh`)

This is a **bash program you run in a terminal**. It is not an agent skill. Do not look for `/setup-ai-tools`.

It installs and configures Serena, CodeGraph, and Graphify (MCP configs, global gitignore, optional gum TUI). Graphify defaults to DeepSeek `deepseek-v4-pro` and is configurable with `--provider` and `--model`.

Home of the script: `bin/setup-ai-tools.sh` in this repo. Always run that file (or a symlink you create). Do not hardcode a volume or username.

Optional: from the parent of this clone, link the script so you can run it next to your other repos:

```bash
cd /path/to/dotskills
ln -sfn "$PWD/bin/setup-ai-tools.sh" "$(dirname "$PWD")/setup-ai-tools.sh"
```

```bash
# From this repo
./bin/setup-ai-tools.sh --no-gum --no-install .

# From the parent folder, if you created the symlink
../setup-ai-tools.sh /path/to/a/repo
```

Interactive (gum): run with no mode flags in a terminal. Flags still work for scripts and CI (`--no-gum`, `--no-install`, `--force`, `--serena-only`, `--codegraph-only`, `--graphify-only`, `--provider <name>`, `--model <name>`).

**Graphify extra:** `uv tool install --force --reinstall "graphifyy[mcp,openai]"`. DeepSeek extract needs the `openai` extra.

**CodeGraph:**

- `.codegraph` missing → `codegraph init`
- `.codegraph` exists → skip
- `--force` and `.codegraph` exists → `codegraph sync` (incremental), not `init`, not a full `index`

**`.graphifyignore`:** Graphify reads this file from the repo being extracted.
- The committed `.graphifyignore` at this repo's root is used when Graphify runs on this repo.
- `setup-ai-tools.sh` creates/updates `.graphifyignore` in each processed repo using the same patterns.
- To change patterns for this repo: edit the committed file.
- To change patterns for other repos: edit the script.

## Adapting this for yourself

1. Fork this repo
2. Replace the personal skills in `skills/` with your own
3. Edit the `OWNED_REPOS` array in `bin/install-skills.sh` — add your own repos, remove mine
4. Edit the `NPX_COMMUNITY` array in `bin/install-skills.sh` — add your own npx collections, remove mine
5. Update the README table above

`bin/install-skills.sh` (and the `./install.sh` shim) needs `git`. `--npx owner/repo` also needs `npx`.
`bin/setup-ai-tools.sh` needs `uv` (for Serena/Graphify) and `npm` (for CodeGraph). `bin/dotskills` uses `gum` for the interactive menu.

## Structure

```
dotskills/
├── bin/
│   ├── dotskills                  # One flow: gum TUI, or skills | tools | all
│   ├── install-skills.sh          # Owned skill clones + personal skills/
│   ├── setup-ai-tools.sh          # Thin dispatcher: flags, lib calls, repo loop
│   └── lib/
│       ├── common.sh              # Shared log, run, add_if_missing helpers
│       ├── paths.sh               # script_dir_of (symlink-safe)
│       ├── detect-tools.sh        # Tool resolution + optional install
│       ├── codegraph.sh           # init / skip / sync
│       ├── graphify.sh            # Extra check, extract, .graphifyignore
│       ├── gitignore.sh           # Global gitignore + untrack MCP configs
│       ├── grok-mcp.sh            # Grok MCP config (TOML) and rules
│       └── write-mcp.sh           # Devin / Cline / Zed MCP + rules orchestrator
├── install.sh                     # Shim → bin/install-skills.sh
├── skills/                        # Personal skills (shipped with this repo)
│   └── setup-rs-guard/            # Optional — not copied unless --with-rs-guard
│       └── SKILL.md
├── .graphifyignore                # Used by Graphify in this repo (script writes the same name elsewhere)
├── docs/
│   ├── PLAN-setup-ai-tools-and-refresh.md
│   ├── PLAN-split-setup-scripts.md      # Unified refactor plan
│   ├── PROMPT-split-setup-scripts.md    # Paste this in the next window
│   └── SOURCES.md                       # Arrays, lib modules, tool chain map
└── README.md
```

## Lib file contracts

Each `bin/lib/*.sh` is sourced by callers and is **not** executed directly. They follow these rules:

- `return 1` on recoverable failure; `exit 1` is reserved for top-level scripts.
- No `set -e` inside lib files; the caller sets the execution policy.
- Lib files may source `common.sh`; they do not depend on machine-absolute paths.
- `write-mcp.sh` is the orchestrator; `gitignore.sh` and `grok-mcp.sh` are single-client/concern modules it sources.

Source clones are stored at `~/.dotskills/sources/` (not committed here).

Any convenience symlink lives **outside** this git repo on purpose (parent folder of the clone).

## Error handling

When a source repository has uncommitted changes, the installer automatically uses `git fetch` followed by `git reset --hard` to ensure a clean update without merge conflicts. This prevents "dirty working directory" errors during updates.
