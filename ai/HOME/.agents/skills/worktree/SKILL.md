---
name: worktree
description: Create and manage git worktrees via ntmux3, including detached (-d) mode for scripted/agent use.
---

# Worktree management with ntmux3

## When to use
- Spinning up a new worktree for a branch or PR.
- Creating a worktree from an agent without stealing the terminal.
- Understanding the worktree directory layout under ~/git/.

## Usage

```
ntmux3 [-d] [GitHub PR URL | [org/[repo/]]branch] [base_dir | file]
ntmux  [-d] [namespace/]session_name [base_dir | file]
```

Neither command has `--help`; invalid or missing arguments print a
usage line to stderr.

## How to create a worktree from an agent

**Important**: `ntmux3` and `ntmux` are shell functions (not
binaries on PATH). They are sourced from `~/.functions/tmux.bash`
via the user's profile. The Bash tool does NOT source the
interactive profile automatically, so you **MUST** run
`source ~/.bashrc` before calling them:

```bash
source ~/.bashrc && session_name=$(ntmux3 -d org/repo/branch-name)
```

Always use `-d` (detached) so the command returns immediately
without attaching to the tmux session.

**Critical**: The first positional argument is a **single
slash-delimited path**, NOT separate arguments. The format is
`org/repo/branch/path/parts` — all as one string. Do NOT pass
org, repo, and branch as separate arguments.

```bash
# CORRECT — single slash-delimited argument:
source ~/.bashrc && ntmux3 -d timvisher-dd/agent-shell-plus/timvisher/my-feature

# WRONG — these are NOT separate arguments:
ntmux3 -d timvisher-dd agent-shell-plus timvisher/my-feature
```

- **stdout**: the tmux session name (capture this).
- **stderr**: an INFO line with the attach command (for humans).
- The worktree directory will be at `~/git/org/repo/branch-name/`.
- If the session already exists, its name is printed without
  creating a new one.
- `-d` skips the "inside tmux" guard, so it works from within an
  existing session.

## References
- See references/worktree.md for directory layout, lower-level
  ntmux usage, and additional examples.
