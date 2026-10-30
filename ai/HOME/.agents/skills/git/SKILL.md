---
name: git
description: Local-only git workflow and safety rules; never mutate remotes, except a draft PR's branch through timvisher_gh.
---

# Git safety policy

## When to use
- Any git operation in this environment.

## Workflow
- Never run commands that mutate remotes (push, force push, delete, etc.).
  The one exception is a draft PR's branch, pushed with `timvisher_gh pr push`
  or `timvisher_gh pr` (see the github skill); never `git push` it yourself.
- Never merge; rebase locally only.
- Never modify git hooks.
- If remote updates are needed, ask the user to run the command.
- Codex: always append `Co-authored-by: Codex <codex@openai.com>` to commit messages unless already present.
- Claude Code: rely on Claude Code attribution settings (enabled by default); the git wrapper validates a `Co-authored-by` trailer matching `<noreply@anthropic.com>` is present.

## References
- See references/git.md for allowed commands and details.
