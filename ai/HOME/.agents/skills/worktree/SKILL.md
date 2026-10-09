---
name: worktree
description: Create and manage git worktrees via ntmux3, including detached (-d) mode for scripted/agent use and terminal (-T) mode to open one in a window the human can watch.
---

# Worktree management with ntmux3

## When to use
- Spinning up a new worktree for a branch or PR.
- Creating a worktree from an agent without stealing the terminal.
- Opening a worktree for the human in a new terminal window (`-T`).
- Understanding the worktree directory layout under ~/git/.

## Usage

```
ntmux3 [-d | -T] [GitHub PR URL | org/repo[/branch] | path] [file]
ntmux3 [-d | -T] org/repo/branch branch-ish
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

## Opening a worktree in a terminal window (-T)

`-T` opens a new terminal window (Ghostty, via the `timvisher
Terminal` AppleScript library) running plain `ntmux3 <args>`, so the
human watches the clone and ends up attached to the tmux session.
Use it when the human asked to see or use the worktree themselves.

```bash
source ~/.bashrc && session_name=$(ntmux3 -T org/repo/branch-name)
```

From an agent (`TIMVISHER_AGENT` set), `-T` gives you the same contract
as `-d`:

- It **blocks** until ntmux3 in the window has created the session
  or failed. That spans the whole clone, so use `run_in_background`
  or a long timeout.
- **stdout**: the tmux session name.
- **stderr**: the window's aictl instructions, streamed live —
  `ntmux3_started`, `ntmux3_worktree_building`,
  `ntmux3_worktree_ready`, `ntmux3_session_ready` (with
  `data.session` and `data.path`), or `ntmux3_failed`.
- **exit status**: 0 once the session is ready, 1 otherwise.
  `ntmux3_failed` covers every way ntmux3 in the window can stop
  before the session is ready: an error, returning early, or being
  interrupted. `ntmux3_terminal_closed` means the window exited without
  reporting, `ntmux3_terminal_timeout` means it did not report within
  `TIMVISHER_NTMUX3_TERMINAL_DEADLINE` seconds (default 3600; ntmux3
  may still be running in the window), and
  `ntmux3_terminal_open_failed` means no window opened.

Without `TIMVISHER_AGENT`, `-T` just opens the window and returns.
`-T` cannot be combined with `-d`: the window has to attach to report
that its session is ready.

The first `-T` from a new process may trigger a macOS Automation
permission prompt that the human has to approve.

## Stacked worktrees

Pass a branch-ish as the second argument to start the new worktree from
an existing branch instead of the trunk. The new worktree is reset to
the base branch's HEAD.

A branch-ish names a branch. It is **complete** when it resolves on its
own (a worktree path, a URL, `org/repo/branch`) and **relative** when it
is a bare branch name that needs a repo for context. Stacking only works
within one repo, so the target supplies that context: a relative base is
a branch of the target's repo.

```bash
# CORRECT — the base is a branch of the target's repo, given bare:
source ~/.bashrc && ntmux3 -d ddoghq/appgate/timvisher/feature-top timvisher/feature-base

# CORRECT — or qualified with the same org/repo as the target:
source ~/.bashrc && ntmux3 -d ddoghq/appgate/timvisher/feature-top ddoghq/appgate/timvisher/feature-base
```

Arg 2 resolves in this order:

- An existing **file** opens in the editor. It is never a stack base.
- A **worktree path** (`/…`, `./…`, `../…`, `~/…`, or a relative
  directory that is a managed worktree) or a **GitHub URL** is used as
  given.
- `org/repo/branch` whose org/repo is the **target's** (org aliases and
  case differences count) is used as given.
- `org/repo/branch` whose org shares an **org alias group** with the
  target's (for example `DataDog` and `ddoghq`) names the same repo, so
  it is moved onto the target's org with a
  `timvisher_git_stack_base_alias_sibling` notice. The notice also says
  when the repo it named is archived.
- **Anything else is a relative branch-ish**, resolved as a branch of
  the target's repo. A base with a
  slash that doesn't start with the target's org/repo is ambiguous —
  `timvisher/feature-base` could also be read as org `timvisher`, repo
  `feature-base` — so it is used as a branch of the target's repo and a
  `timvisher_git_stack_base_inherited` notice says so. Qualify the base
  to make the intent explicit and silence the notice.
- A value that is neither an existing file nor a branch-ish (for
  example, one containing a space) is ignored with an
  `ntmux3_arg2_ignored` notice, and nothing is stacked.

A base that explicitly names a *different* repo (a URL or worktree path
into another repo) fails with `timvisher_git_stack_base_repo_mismatch`,
which names the repo it resolved to and suggests a corrected base.

The base branch must already exist, as a local branch or on origin. A
missing base fails with `timvisher_git_stack_base_missing` instead of
being created off the trunk, so a misspelled base is caught rather than
quietly giving you a worktree on the trunk.

The target must be a new branch. Stacking resets the target to the
base's HEAD, so stacking a branch that already exists would drop its own
commits from your local copy, and `ntmux3 -d org/repo <base>` would move
your local trunk onto the base. Neither is allowed:

- The trunk fails with `timvisher_git_stack_target_is_trunk`, whether or
  not its worktree already exists.
- Any other branch that exists locally or on origin fails with
  `timvisher_git_stack_target_exists`.

Re-running is still safe. If the target worktree already exists it is
left alone rather than re-stacked, and an interrupted stack (an
`x.ntmux3-building` marker in the target) is resumed.

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
