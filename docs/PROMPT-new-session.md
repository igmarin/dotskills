# Prompt — start this in the dotskills repo only

Copy everything below the line into a **new** Grok (or other agent) session. Set the working directory to the dotskills repository root.

Do not start this from `rs-guard` or `Projects/` as the workspace.

---

Read `docs/PLAN-setup-ai-tools-and-refresh.md`. Implement it in this repo. It is the source of truth. Do not second-guess it.

Work only in the dotskills repository. The one exception is creating or replacing the symlink at the parent directory's `setup-ai-tools.sh` → this repo's `bin/setup-ai-tools.sh`.

## Do

1. Move the parent directory's `setup-ai-tools.sh` to `bin/setup-ai-tools.sh` (executable). Delete the original file. Put a symlink at the old path.
2. In that script, install Graphify as `graphifyy[mcp,openai]` (DeepSeek extract needs the `openai` extra). For CodeGraph, run `init` only if `.codegraph` is missing. If `.codegraph` exists, skip it. If `--force` is set and `.codegraph` exists, run `codegraph sync` (not `init`, not full `index`). Update the header comment table.
3. Slim `install.sh` default `SOURCE_REPOS` to repos I author (`agnostic-planning-skills`, `ruby-core-skills`, `rails-agent-skills`) plus **generic** personal `skills/`. Do not default-install addyosmani/blueprint (`--with-community`). Elixir-phoenix-skills is optional/off (work-only). **`setup-rs-guard` is optional/off** (`--with-rs-guard`). This repo is public. Forks must not get a personal code-review tool by default. Do not copy `~/.agents/skills` from this machine into the repo. Update `--help` and README for the npx/marketplace vs `./install.sh` split and the optional extras.
4. Refresh `skills/setup-rs-guard/SKILL.md` to rs-guard **v1.7.0** and **`deepseek-v4-pro`**. This keeps the opt-in extra current. Verify facts against the rs-guard repository (`docs/CONFIGURATION.md`, `docs/USAGE.md`, current schema). Replace any stale machine-specific paths. Do not invent config keys. Keep the file in the tree. Do not install it on a default `./install.sh`.
5. Update `README.md`. Cover the script, symlink, extras including **optional rs-guard**, the CodeGraph rule, installer sources, and the structure tree.

## Do not

- Create a `SKILL.md` for `setup-ai-tools.sh`.
- Edit the rs-guard codebase.
- Run a full multi-repo setup pass unless you need one repo to verify CodeGraph skip/`sync`.
- Commit unless I ask.

## Proof

- `bash -n bin/setup-ai-tools.sh`
- `test -L /Volumes/minimini/Developer/Projects/setup-ai-tools.sh` and it resolves to `bin/setup-ai-tools.sh`
- `./bin/setup-ai-tools.sh --no-gum --no-install .` does not print CodeGraph "Initializing" / `init` when `.codegraph` already exists
- README and `install.sh --help` match the slim default source list
