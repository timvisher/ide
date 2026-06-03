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

## When is the worktree ready? (read this before editing)

**The worktree is ready when `ntmux3 -d` completes — NOT when the
directory appears.** Creating a worktree is a long-running operation
(clone, checkout, maintenance/gc, and — for stacked worktrees — a
final `git reset --hard`). To make premature use impossible, ntmux3
builds the worktree in a **hidden temp sibling** and only moves it to
its canonical `~/git/org/repo/branch/` path as the very last step. So:

- The canonical path **does not exist** until the worktree is fully
  ready. Do not pre-create it or poll for "directory has files."
- When you run `ntmux3 -d` in the background, **wait for the task to
  complete** before touching the worktree. As an agent you also get
  two structured signals on stderr:
  - `ntmux3_worktree_building` (a `warning`-level notice) at the
    start — the run is long and the worktree is not ready yet.
  - `ntmux3_worktree_ready` (an `info` instruction with the path)
    when it is safe to use and edit.
- While a worktree is mid-build (or mid-stack-reset), it carries an
  `x.ntmux3-building` marker file in its root. Its presence means
  "not ready"; it is removed once the worktree is ready.

Editing a worktree before it is ready races the build, and a stacked
worktree's `reset --hard` will silently discard those edits.

<!--
  ide-8hi: the prevention above (temp-build+move, the building marker,
  and the building/ready instructions) is INSTRUCTION-based — it relies
  on the agent waiting for the completion signal. If we observe agents
  still editing worktrees before they are ready, escalate to a hard
  guard: a PreToolUse hook on Write/Edit that refuses when the target
  file's worktree root contains an x.ntmux3-building marker. That makes
  premature edits impossible rather than merely discouraged.
-->

## References
- See references/worktree.md for directory layout, lower-level
  ntmux usage, and additional examples.
