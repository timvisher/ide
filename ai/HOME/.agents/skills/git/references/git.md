# Git

## Non-Negotiable Rules

- Agents must NEVER run any git command that mutates a remote.
  This includes (but is not limited to): `git push`, `git push --force`,
  `git push --delete`, `git push --mirror`, `git send-pack`.
- For any GitHub interactions (PRs, releases, repo metadata, checks), use `gh`
  only; see `github-mcp.md`.
- Agents must NEVER merge. Always rebase locally.
- Agents must NEVER modify git hooks or hook configuration.
  Do not edit `.git/hooks`, `core.hooksPath`, or `/usr/local/dd/global_hooks`.
- Agents must NEVER change or update remote state. That is user-only work.

If remote updates are needed, ask the user to run the command and then continue
with local-only work.

## Remote Read-Only Commands (Allowed)

Commands that contact remotes but do NOT modify them are allowed:
- `git fetch`
- `git pull --rebase`
- `git ls-remote`
- `git clone`

## Local-Only Workflow (Allowed)

Safe local commands:
- `git status -sb`
- `git diff` / `git diff --staged`
- `git log --oneline -n <N>`
- `git show <rev>`
- `git add <path>`
- `git commit -m "..."`
- `git rebase <local-ref>` (no network access)

Notes:
- Do not amend commits unless the user explicitly asks.
- Do not use destructive commands unless the user explicitly requests.

## Rebase Policy

- Never use `git merge`.
- If integrating upstream work is required, ask the user to fetch/pull.
  Then rebase locally onto the updated ref (e.g., `origin/master`).

## Branch Diffs and Logs

When examining what a branch has changed — for commits, PRs, reviews,
commit cleanup, or any other purpose — ALWAYS use `@{u}...` (the
upstream tracking ref).  Never hardcode `main..HEAD`, never use
`git merge-base`, never guess the base branch name, never use
raw SHAs in range expressions.  The git wrapper enforces this.

```bash
git log '@{u}...'
git diff '@{u}...'
```

This is correct regardless of upstream branch name and works after rebases.

## When In Doubt

If you are unsure whether a git command might mutate a remote, do not run it.
Ask the user to run it instead.

## Git Commits

- Prefer small, focused commits that make one logical change.
- When multiple changes are staged, create separate commits for each logical change.
- Each commit should be self-contained and independently understandable.
- Never use interactive git commands (`git add -p`, `git rebase -i`, etc.) - they require user interaction.
- Codex: always append `Co-authored-by: Codex <codex@openai.com>` unless already present.
- Claude Code: rely on Claude Code attribution settings (enabled by default); the git wrapper validates a `Co-authored-by` trailer matching `<noreply@anthropic.com>` is present.
- Gemini: always append a `Co-authored-by` trailer matching `<noreply@google.com>` to commit messages unless already present.

## What Not to Commit

- Do not commit planning documents, working notes, or migration plan files (e.g., `TERRAFORM_MODULES_MIGRATION.md`).
- Keep these as untracked files for reference during work sessions.
- `todo.org` is gitignored and should remain local to each developer.
