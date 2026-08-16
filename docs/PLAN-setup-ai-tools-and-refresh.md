# Plan: move setup-ai-tools into dotskills and refresh the repo

Decided 2026-08-15. Do the implementation in this repo only (`/Volumes/minimini/Developer/Projects/dotskills`). Do not keep editing `rs-guard` or a copy of the script under `Projects/`, except for the symlink.

Source script today: `/Volumes/minimini/Developer/Projects/setup-ai-tools.sh`

---

## Context

`setup-ai-tools.sh` installs Serena, CodeGraph, and Graphify locally. It handles the gum TUI, MCP configs, and global gitignore. It currently lives directly under `Developer/Projects/`. This repo (`dotskills`) is the personal agent-tooling home, so the script belongs here. Because this repo is public, the default install must work for any fork that never uses rs-guard. Refresh `setup-rs-guard` to **1.7.0** / **`deepseek-v4-pro`**, but keep it as an **opt-in** extra, not something `./install.sh` always copies.

---

## Scope options

We considered three options:

| Option | Meaning | Doing? |
|--------|---------|--------|
| **A** | Move the shell script. Stop. | Too small. |
| **B** | Move the script, then add a `SKILL.md` so an agent can invoke `/setup-ai-tools` like `/graphify`. | No. The script is a human/local installer you run in a terminal. Agents do not need a skill wrapper. A README section is enough. |
| **C** | Move the script, document it, and refresh what is already here (`setup-rs-guard`, installer notes). | Yes. We are not inventing a new skill. |

`setup-rs-guard` is a skill because an agent follows its steps when you say "add AI review to this repo." `setup-ai-tools.sh` is a bash program you run yourself. They serve different purposes.

---

## Settled decisions

1. **Script home:** `bin/setup-ai-tools.sh` in this repo.
2. **Old path:** Delete `/Volumes/minimini/Developer/Projects/setup-ai-tools.sh`. Create a **symlink** at that same path pointing to `dotskills/bin/setup-ai-tools.sh`, so `Projects/setup-ai-tools.sh` still works when adding new repos.
3. **No new personal skill** for the installer. Document it in `README.md`.
4. **`setup-rs-guard` is optional.** This is a public repo, so forks should not get igmarin-specific rs-guard glue (GitHub user, binary paths, project board) unless they ask. Refresh the skill to **v1.7.0** and **`deepseek-v4-pro`** from `/Volumes/minimini/Developer/Projects/rs-guard` (not `~/Developer/Nebula/rs-guard`) so the extra is current. Install it only with something like `--with-rs-guard`. Re-read the real rs-guard docs before editing the skill. Do not invent `.reviewer.toml` keys.
5. **Graphify install extra:** `uv tool install --force --reinstall "graphifyy[mcp,openai]"`. DeepSeek extract uses the OpenAI-compatible client; missing `openai` is why semantic chunks failed on `rs-nightshift`.
6. **CodeGraph:** `init` only when `.codegraph` is missing. If the index exists, skip. If `--force` and the index exists, run `codegraph sync` (incremental), not `init` and not a full `index`.
7. **Installer sources vs npx:** see below.
8. **Elixir skills:** optional, not in the default source list. Work-only.
9. **rs-guard / `setup-rs-guard`:** optional, same reason as elixir. It is personal toolchain, not a requirement of the public installer.

---

## install.sh vs npx

You can now install many skills with `npx` / marketplaces. `install.sh` **copies** third-party trees into `~/.agents/skills/` and will overwrite whatever npx put there.

**Default `SOURCE_REPOS` should be only repos you author:**

- `igmarin/agnostic-planning-skills`
- `igmarin/ruby-core-skills`
- `igmarin/rails-agent-skills`
- plus **generic** personal skills under `skills/` (always last, always win). **`setup-rs-guard` is not in that default copy.**

**Do not** clone third-party collections on a default `./install.sh`. Use `npx skills install -g <slug> --all`. Do not clone `addyosmani/agent-skills` or `owainlewis/blueprint` by default. Those belong to npx / the marketplace on this machine.

**Do not** scrape `~/.agents/skills` from this machine into the public repo. That mix is personal + work + marketplace and is not a source of truth.

**Optional extras** (documented, off by default):

- `--with-community` — restore the old third-party clones.
- `--with=elixir-phoenix-skills` (or a commented example in `install.sh`) — work machine only.
- `--with-rs-guard` — install the refreshed `setup-rs-guard` skill. This is your local code-review runbook, not for every fork.

README must say: personal/owned skills via `./install.sh`; everything else via npx/marketplace.

---

## Errors to fix in the moved script

From the `rs-nightshift` run:

| Symptom | Fix |
|---------|-----|
| Graphify: `the 'openai' package is required for this backend` | Install `graphifyy[mcp,openai]`, not `[mcp]` only. |
| Graphify: 9/9 semantic files produced no nodes | This follows from the missing extra. Once the extra is present, extract can succeed. |
| Graphify warning: `.cline_mcp_servers.json`, `mcp_config.json`, `settings.json` treated as "code" with zero nodes | Those are MCP configs the script itself writes. Ignore them. Do not pass them as code. |
| CodeGraph: `Already initialized` banner after `init` | Do not call `init` when `.codegraph` exists. `--force` → `sync`. |

---

## Tasks (order)

### 1. Land the script in `bin/` and leave a Projects symlink

Move (do not copy-and-forget) `Projects/setup-ai-tools.sh` → `bin/setup-ai-tools.sh`. `chmod +x`. Replace the old path with a symlink to the new file. Commit only inside this git repo; the symlink lives outside git on purpose.

### 2. Apply the two script behavior fixes

Use the Graphify extra `[mcp,openai]`. Apply the CodeGraph `init` / `sync` rules above. Update the header comment table to match.

### 3. Slim `install.sh` and document optional sources

Default = owned repos only. Add optional community, elixir, and rs-guard as documented flags. The default copy of `skills/` must skip `setup-rs-guard` unless `--with-rs-guard`. Update `install.sh --help` and `README.md`.

### 4. Refresh `skills/setup-rs-guard/SKILL.md` (opt-in extra)

Use v1.7.0, `deepseek-v4-pro`, and current binary/config/workflow facts from `/Volumes/minimini/Developer/Projects/rs-guard`. Fix the stale Nebula path. Do not invent `.reviewer.toml` keys. Keep the skill in the tree; do not install it by default.

### 5. README

Add a section explaining what `bin/setup-ai-tools.sh` is, how to run it (gum vs flags), the Projects symlink, the Graphify extra, and the CodeGraph sync rule. Document optional extras: community, elixir, and rs-guard. The structure tree should mark `setup-rs-guard` as optional.

---

## Out of scope

- Wrapping the installer as a `SKILL.md`.
- Running setup against every project from this session.
- Harvesting `~/.agents/skills` into this repo.
- Adding elixir-phoenix-skills or `setup-rs-guard` to the default install.
- Changing rs-guard itself.
- Packing repos with Repomix during setup.

---

## Done when

- `bin/setup-ai-tools.sh` exists and is executable.
- `Projects/setup-ai-tools.sh` is a symlink to that file.
- `bash -n bin/setup-ai-tools.sh` passes.
- Header comments list `graphifyy[mcp,openai]` and the CodeGraph rule.
- `install.sh` default list is owned repos only.
- `setup-rs-guard` documents 1.7.0 and `deepseek-v4-pro`, and is not installed unless `--with-rs-guard`.
- README describes the script and the install/npx split.
- A fresh `./bin/setup-ai-tools.sh --no-gum --no-install <one-repo>` does not re-`init` CodeGraph when `.codegraph` already exists.
