# Prompt — split setup-ai-tools (next window)

Cwd: the `dotskills` clone. Do not start from `rs-guard` or a parent `Projects/` folder as the workspace.

---

Read `docs/PLAN-split-setup-scripts.md` and implement it. That file is the source of truth. Do not re-litigate it.

Work only in this repo. Do not edit `rs-guard`. Do not harvest `~/.agents/skills`. Do not commit unless asked.

## Do

Extract `bin/setup-ai-tools.sh` into `bin/lib/` **one file at a time**, in the plan’s order:

1. `detect-tools.sh`
2. `codegraph.sh`
3. `graphify.sh`
4. `write-mcp.sh`
5. Thin `setup-ai-tools.sh` + README tree

Prove after each extract (`bash -n`, CodeGraph skip when `.codegraph` exists).

## Do not

- Add a second gum TUI (`bin/dotskills` is the one configuration flow)
- Split `bin/install-skills.sh`
- Create a `SKILL.md` for the installer
- Change Graphify extras, CodeGraph init/skip/sync, skill source list, or npx community
- Run a full multi-repo setup pass
- Mix behavior changes with an extract

## Proof

- `bash -n bin/dotskills bin/setup-ai-tools.sh bin/install-skills.sh bin/lib/*.sh`
- `./bin/dotskills tools --no-gum --no-install .` does not print CodeGraph “Initializing” / `init` when `.codegraph` already exists
- `./bin/dotskills --help` still describes one gum flow
