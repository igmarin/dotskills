---
name: setup-rs-guard
description: >
  Adds rs-guard AI code review to any of igmarin's GitHub repos: GitHub Actions PR workflow,
  pre-commit hook, .reviewer.toml config, bundled binaries with checksums, branch protection,
  and GitHub labels/issues/project board. Use when setting up rs-guard on a new repo, or when
  asked to "add AI review", "set up rs-guard", or "mirror the rails-agent-skills review setup".
metadata:
  version: 1.0.0
---

# Setup rs-guard AI Review

Adds rs-guard to a repo, mirroring the `rails-agent-skills` reference implementation.

## Quick Reference

- **Binary**: `~/.cargo/bin/rs-guard` (v1.0.0) — also bundled at `bin/rs-guard-{platform}`
- **Config**: `.reviewer.toml` — top-level fields only (see schema below)
- **Workflow**: `.github/workflows/rs-guard-review.yml`
- **Hook**: `hooks/pre-commit-rs-guard` + `hooks/hooks.json`
- **Prompt**: `.github/review-prompt.md`

---

## Checklist

- [ ] Step 1 — Build and bundle binaries
- [ ] Step 2 — Create `.reviewer.toml`
- [ ] Step 3 — Write `.github/review-prompt.md`
- [ ] Step 4 — Write `.github/workflows/rs-guard-review.yml`
- [ ] Step 5 — Write `hooks/pre-commit-rs-guard` + `hooks/hooks.json`
- [ ] Step 6 — Create `bin/CHECKSUMS.txt`
- [ ] Step 7 — GitHub labels
- [ ] Step 8 — GitHub issues + project board
- [ ] Step 9 — Branch protection ruleset

---

## Step 1 — Build and Bundle Binaries

rs-guard source lives at `~/Developer/Nebula/rs-guard`.

```bash
# macOS arm64 (native)
cd ~/Developer/Nebula/rs-guard
cargo build --release
cp target/release/rs-guard /PATH/TO/REPO/bin/rs-guard-macos-arm64

# Linux x86_64 (cross-compile)
cargo install cross
cross build --release --target x86_64-unknown-linux-musl
cp target/x86_64-unknown-linux-musl/release/rs-guard /PATH/TO/REPO/bin/rs-guard-linux-x64

# Checksums
cd /PATH/TO/REPO/bin
shasum -a 256 rs-guard-macos-arm64 rs-guard-linux-x64 > CHECKSUMS.txt
```

`CHECKSUMS.txt` must include: SHA-256 of each binary, rs-guard version, build date, and source repo.

---

## Step 2 — `.reviewer.toml`

**Schema: top-level fields only. No `[review]` wrapper. No `[provider.deepseek]` section.**
Both of those are invalid and cause CI failures.

```toml
provider = "deepseek"
model = "deepseek-chat"
temperature = 0.1
```

rs-guard auto-discovers this file from the repo root — no `--config` flag needed.

---

## Step 3 — `.github/review-prompt.md`

Sections to include (adapt section 3 for the repo's domain):

1. **Role & scope** — who the reviewer is, what the repo contains
2. **Skill Structure** — frontmatter rules (blocking vs suggestion), valid `type` values
3. **Domain-specific conventions** — e.g. planning skills check for PRD template compliance;
   Rails repos check for frozen_string_literal, service response format, etc.
4. **Cross-cutting rules** — CHANGELOG must be updated, no time-sensitive info in skills,
   `metadata.version` must be present

Use `metadata.version` **must** (not "should") — rs-guard treats "must" as blocking.

---

## Step 4 — `.github/workflows/rs-guard-review.yml`

```yaml
name: rs-guard PR Review

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

permissions:
  contents: read
  pull-requests: write

concurrency:
  group: rs-guard-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  review:
    if: github.event.pull_request.draft == false
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Make rs-guard executable
        run: chmod +x bin/rs-guard-linux-x64

      - name: Run rs-guard review
        run: bin/rs-guard-linux-x64 --prompt-file .github/review-prompt.md --provider deepseek
        env:
          DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          REPO_FULL_NAME: ${{ github.repository }}
```

**Notes:**
- `dtolnay/rust-toolchain` and `actions/cache` are NOT needed — use the bundled binary directly.
- `persist-credentials: false` — required; rs-guard uses `GITHUB_TOKEN` from env, not git credentials.
- `REPO_FULL_NAME` and `PR_NUMBER` are required by rs-guard to post the review via GitHub API.
- No build step — the bundled `bin/rs-guard-linux-x64` is used directly.

---

## Step 5 — `hooks/pre-commit-rs-guard` + `hooks/hooks.json`

**`hooks/pre-commit-rs-guard`** — key patterns:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"  # MUST use $REPO_ROOT, not relative path

resolve_binary() {
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)  echo "$REPO_ROOT/bin/rs-guard-macos-arm64" ;;
    Linux-x86_64)  echo "$REPO_ROOT/bin/rs-guard-linux-x64"  ;;
    *)             echo "" ;;
  esac
}
# ... fall back to PATH then ~/.cargo/bin/rs-guard
# ... check for any of: DEEPSEEK_API_KEY OPENAI_API_KEY KIMI_API_KEY DASHSCOPE_API_KEY OPENROUTER_API_KEY

"$RS_GUARD_BIN" \
  --diff-file "$DIFF_FILE" \
  --prompt-file "$REPO_ROOT/.github/review-prompt.md" \  # absolute path via $REPO_ROOT
  --dry-run \
  2>&1 || echo "[rs-guard] Review exited with a non-zero code (advisory only — commit proceeds)."
```

Do NOT hardcode `--provider deepseek` — rs-guard reads it from `.reviewer.toml`.

**`hooks/hooks.json`** — PreCommit only (no SessionStart unless the repo already has one):

```json
{
  "hooks": {
    "PreCommit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-commit-rs-guard",
            "async": false
          }
        ]
      }
    ]
  }
}
```

No extra quotes around `command` — just the bare `${CLAUDE_PLUGIN_ROOT}/hooks/pre-commit-rs-guard`.

---

## Step 6 — `bin/CHECKSUMS.txt`

```
# rs-guard binaries — SHA-256 checksums
# Version: 1.0.0
# Built: YYYY-MM-DD
# Source: https://github.com/igmarin/rs-guard

<sha256>  rs-guard-macos-arm64
<sha256>  rs-guard-linux-x64
```

---

## Step 7 — GitHub Labels

```bash
gh label create "todo"        --repo igmarin/REPO --color "#0E8A16" --description "Issue is ready to be worked on"
gh label create "in-progress" --repo igmarin/REPO --color "#0075CA" --description "Issue is actively being worked on"
gh label create "done"        --repo igmarin/REPO --color "#6F42C1"  --description "Issue is complete"
```

---

## Step 8 — GitHub Issues + Project Board

Create one issue per deliverable, label `todo`, then add to the project board:

```bash
# Create issues
gh issue create --repo igmarin/REPO --title "feat: Add rs-guard pre-commit hook" --label "todo" --body "..."
gh issue create --repo igmarin/REPO --title "feat: Add rs-guard GitHub Actions PR review workflow" --label "todo" --body "..."
gh issue create --repo igmarin/REPO --title "feat: Write rs-guard review prompt" --label "todo" --body "..."
gh issue create --repo igmarin/REPO --title "chore: Add branch protection on main" --label "todo" --body "..."

# Add to project board (get project ID first)
gh project list --owner igmarin
gh project item-add PROJECT_ID --owner igmarin --url https://github.com/igmarin/REPO/issues/N

# Close issues as done when work is complete
gh issue edit N --repo igmarin/REPO --add-label "done" --remove-label "todo"
gh issue close N --repo igmarin/REPO
```

---

## Step 9 — Branch Protection Ruleset

Blocks deletion and force-push on `main`. Does NOT require PRs (breaks Tessl's `git push` workflow).

```bash
gh api repos/igmarin/REPO/rulesets --method POST --input - <<'EOF'
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "bypass_actors": [
    { "actor_id": 39272, "actor_type": "Integration", "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" }
  ]
}
EOF
```

**No `required_pull_request` rule** — this breaks Tessl's `git push origin HEAD:main` on free-plan accounts.

---

## Secrets Required

These must already be set on the repo before the workflow runs:

| Secret | Value |
|--------|-------|
| `DEEPSEEK_API_KEY` | DeepSeek API key |
| `GH_PAT` | Fine-grained PAT — Contents: read+write (needed only if workflow pushes) |

`GITHUB_TOKEN` is automatic and sufficient for posting PR reviews.

---

## Gotchas (Lessons from First Implementation)

| Mistake | Correct approach |
|---------|-----------------|
| `.reviewer.toml` with `[review]` wrapper | Top-level fields only: `provider`, `model`, `temperature` |
| `.reviewer.toml` with `[provider.deepseek]` section | Invalid — that section doesn't exist |
| `--provider deepseek` hardcoded in hook | Drop it — rs-guard reads `.reviewer.toml` automatically |
| Relative `--prompt-file` path in hook | Always use `$REPO_ROOT/.github/review-prompt.md` |
| Extra quotes in `hooks.json` command | `"command": "${CLAUDE_PLUGIN_ROOT}/hooks/..."` — no wrapping quotes |
| `dtolnay/rust-toolchain` + `actions/cache` in workflow | Not needed — use bundled binary directly |
| `|| true` to swallow rs-guard failures | Use `|| echo "[rs-guard] ..."` to surface the message |
| `metadata.version` "should" in prompt | Use "must" — rs-guard treats "should" as suggestion, "must" as blocking |
| Empty PR review comment after "CI passed" | rs-guard posts APPROVE via review API, not as a comment — this is correct |

---

## Integration Pattern

After setup, every PR triggers:

```
git push → PR opened → rs-guard-review.yml → rs-guard reads .reviewer.toml
  → fetches diff via GITHUB_TOKEN → calls DeepSeek → posts review via PR Reviews API
```

Local: every `git commit` → `hooks/pre-commit-rs-guard` → rs-guard `--dry-run` → prints advisory (never blocks).
