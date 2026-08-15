# Prompt — start this in the dotskills repo only

Copy everything below the line into a **new** Grok (or other agent) session
whose cwd is `/Volumes/minimini/Developer/Projects/dotskills`.

Do not start this from `rs-guard` or `Projects/` as the workspace.

---

Read `docs/PLAN-setup-ai-tools-and-refresh.md` and implement it in this repo. That file is the source of truth. Do not re-litigate it.

Work only in `/Volumes/minimini/Developer/Projects/dotskills`. The one exception is creating/replacing the symlink at `/Volumes/minimini/Developer/Projects/setup-ai-tools.sh` → this repo’s `bin/setup-ai-tools.sh`.

## Do

1. Move `/Volumes/minimini/Developer/Projects/setup-ai-tools.sh` to `bin/setup-ai-tools.sh` (executable). Delete the original file. Put a symlink at the old path.
2. In that script: install Graphify as `graphifyy[mcp,openai]` (DeepSeek extract needs the `openai` extra). CodeGraph: `init` only if `.codegraph` is missing; if it exists, skip; if `--force` and it exists, `codegraph sync` (not `init`, not full `index`). Update the header comment table.
3. Slim `install.sh` default `SOURCE_REPOS` to repos I author (`agnostic-planning-skills`, `ruby-core-skills`, `rails-agent-skills`) plus **generic** personal `skills/`. Do not default-install addyosmani/blueprint (`--with-community`). Elixir-phoenix-skills is optional/off (work-only). **`setup-rs-guard` is optional/off** (`--with-rs-guard`) — this repo is public; forks must not get a personal code-review tool by default. Do not copy `~/.agents/skills` from this machine into the repo. Update `--help` and README for the npx/marketplace vs `./install.sh` split and the optional extras.
4. Refresh `skills/setup-rs-guard/SKILL.md` to rs-guard **v1.6.0** and **`deepseek-v4-pro`** so the opt-in extra is current. Verify facts against `/Volumes/minimini/Developer/Projects/rs-guard` (`docs/CONFIGURATION.md`, `docs/USAGE.md`, current schema). Replace the stale `~/Developer/Nebula/rs-guard` path. Do not invent config keys. Keep the file in the tree; do not install it on a default `./install.sh`.
5. Update `README.md` (script, symlink, extras including **optional rs-guard**, CodeGraph rule, installer sources, structure tree).

## Do not

- Create a `SKILL.md` for `setup-ai-tools.sh`.
- Edit the rs-guard codebase.
- Run a full multi-repo setup pass unless you need one repo to verify CodeGraph skip/`sync`.
- Commit unless I ask.

## Proof

- `bash -n bin/setup-ai-tools.sh`
- `test -L /Volumes/minimini/Developer/Projects/setup-ai-tools.sh` and it resolves to `bin/setup-ai-tools.sh`
- `./bin/setup-ai-tools.sh --no-gum --no-install .` does not print CodeGraph “Initializing” / `init` when `.codegraph` already exists
- README and `install.sh --help` match the slim default source list
