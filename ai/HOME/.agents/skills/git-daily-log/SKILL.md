---
name: git-daily-log
description: Review daily git activity using author-date log queries and related cautions.
---

# Git daily log review

## When to use
- Summarizing commits for a specific day.
- Auditing author-date activity after rebases.

## Workflow
- Use `active-work-context` to identify active repos (tmux sessions, open PRs, and local changes).
- Use the reference commands for author-date filtering across those repos.
- Remember `git log --since/--until` uses author date, not committer date.

## References
- See references/git-daily-log.md for commands and notes.
