# dotskills

My personal agent skill ecosystem — one installer that bootstraps everything I need to work with AI coding agents across any project.

## What this is

Agent skills are structured instruction files (`SKILL.md`) that teach AI coding agents how to do specific things: write a PRD, run a TDD loop, set up rs-guard, review code. They live in `~/.agents/skills/` and are loaded on demand by agents like Claude Code, Devin, and others.

This repo does two things:

1. **Holds my personal skills** — skills that are specific to my setup, my GitHub repos, and my toolchain. These live in `skills/` here.
2. **Installs my full skill ecosystem** — a single `install.sh` that clones and installs skills from all the repos I depend on, in the right order.

## Why public

Skills are configuration for AI agents, not secrets. Sharing them openly means:

- Others can see the patterns and adapt them
- The install approach is reproducible on any machine
- It's a useful reference for anyone building their own skill ecosystem

## Why "personal"

The skills in `skills/` here are **opinionated to my specific setup**. For example, `setup-rs-guard` references my GitHub username, my repo names, my specific `.reviewer.toml` schema discoveries, and the exact mistakes I made the first time. These are not general-purpose skills — they're a personal runbook.

If you find them useful, fork this repo and replace the personal references with your own.

## Skill ecosystem

The installer pulls from these sources, in priority order:

| Priority | Source | What it provides |
|----------|--------|-----------------|
| 1 (highest) | `dotskills/skills/` (this repo) | Personal glue skills — always win on collision |
| 2 | [`igmarin/rails-agent-skills`](https://github.com/igmarin/rails-agent-skills) | Rails-specific TDD, DDD, engines, GraphQL |
| 2 | [`igmarin/ruby-core-skills`](https://github.com/igmarin/ruby-core-skills) | Shared Ruby process skills |
| 2 | [`igmarin/agnostic-planning-skills`](https://github.com/igmarin/agnostic-planning-skills) | Language-agnostic planning, PRDs, sprints |
| 3 | [`google/skills`](https://github.com/google/skills) | Google Cloud + Gemini API skills (GKE, Cloud Run, BigQuery, WAF, etc.) |
| 3 | [`cloudflare/skills`](https://github.com/cloudflare/skills) | Cloudflare Workers, Agents SDK, Durable Objects, Wrangler |
| 4 | [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills) | General engineering skills (23 skills) |
| 5 (lowest) | [`owainlewis/blueprint`](https://github.com/owainlewis/blueprint) | Minimal SDLC baseline (spec, plan, tdd, review) |

**Collision policy:** when two sources provide a skill with the same name, the higher-priority source wins. My domain repos override the general ones; my personal skills override everything.

## Personal skills

| Skill | What it does |
|-------|-------------|
| [`setup-rs-guard`](skills/setup-rs-guard/SKILL.md) | Full runbook for adding rs-guard AI PR review to any of my repos: GitHub Actions workflow, pre-commit hook, `.reviewer.toml` config, bundled binaries, branch protection, and project board. Includes a gotchas table of everything that went wrong the first time. |

## Install

```bash
git clone https://github.com/igmarin/dotskills.git
cd dotskills
./install.sh
```

This will:

1. Create `~/.dotskills/sources/` and clone all source repos there
2. Copy all skills into `~/.agents/skills/` in priority order
3. Install personal skills last (they always win)

To update everything later:

```bash
./install.sh
```

Re-running is safe — it pulls the latest from each source and re-copies.

### Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would happen without making changes |
| `--verbose` | Log each command as it executes |
| `--only=slug1,slug2` | Install only specified sources (comma-separated) |
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

Installs only the specified sources. Personal skills from this repo are always installed regardless of the `--only` filter (they have the highest priority).

### Uninstall

```bash
./install.sh --uninstall
```

Removes all skills from `~/.agents/skills/` with a confirmation prompt.

## Adapting this for yourself

1. Fork this repo
2. Replace the personal skills in `skills/` with your own
3. Edit the `SOURCE_REPOS` array in `install.sh` — add your own repos, remove mine
4. Update the README table above

The install script requires `git` (standard on macOS/Linux).

## Structure

```
dotskills/
├── install.sh             # Ecosystem bootstrap installer
├── skills/                # Personal skills (shipped with this repo)
│   └── setup-rs-guard/
│       └── SKILL.md
└── README.md
```

Source clones are stored at `~/.dotskills/sources/` (not committed here).

## Error handling

When a source repository has uncommitted changes, the installer automatically uses `git fetch` followed by `git reset --hard` to ensure a clean update without merge conflicts. This prevents "dirty working directory" errors during updates.

