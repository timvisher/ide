# Beads and Topics (Required)

## Architecture

Beads uses per-topic Dolt database servers for issue tracking across repos.

- **Topics**: Each project/repo maps to a "topic" directory under
  `~/Documents/datadog/projects/<topic>/`. Each topic has a `.beads/`
  subdirectory containing its own Dolt database, server state files, and
  metadata (prefix, database name, etc.).
- **Per-topic Dolt servers**: Each topic runs its own Dolt server on a
  hash-derived port (auto-started by `bd`, idle-stopped after 30 min).
  Each topic gets its own database (e.g., `beads_ide`, `beads_appgate`)
  inside its `.beads/dolt/` directory.
- **Redirect**: Each repo worktree has `.beads/redirect` pointing to its
  topic's `.beads/` directory. This is how `bd` knows which database to use.
- **`timvisher_bd_topics set <topic>`** writes the redirect file. If the
  redirect is stale, `bd` commands will fail with errors like "table not
  found" or "issue_prefix missing". Re-running `set` fixes this.
- **`bd dolt start|stop|status`** manages the current topic's Dolt server
  directly (the worktree redirect routes to the correct topic).

Understanding this makes troubleshooting straightforward: most errors mean
either the redirect is wrong (fix with `set`) or the topic's server is down
(fix with `bd dolt stop --force` + `bd dolt start`).

## NEVER do these things

- **NEVER run `bd init` or `bd init --force`** to fix errors. These are for
  brand-new repos only. In worktrees they always fail with "cannot run bd
  init from within a git worktree". The fix for "issue_prefix missing" or
  "database not initialized" is `timvisher_bd_topics set <topic>`.
- **NEVER run `bd doctor --fix --yes`** without user approval.
- **NEVER manipulate `.beads/` contents directly** — no `cat`, `ls`, `rm`,
  `mkdir` inside `.beads/`. All state is managed by `bd` and
  `timvisher_bd_topics`.
- **NEVER fall back to TodoWrite** when `bd` fails. Fix `bd` using the
  recovery steps below, or ask the user.

## Recovery: when bd commands fail OR return suspicious results

**Triggers** — run recovery if ANY of these happen:
- Explicit database errors ("table not found", "issue_prefix config is
  missing", "database not initialized", connection refused, etc.)
- **Silent empty results**: `bd list` returns nothing, `bd ready` says
  "No open issues", or any `bd` query returns empty when you have reason
  to believe issues exist (e.g., `bd prime` showed a valid redirect, or
  the user told you issues exist).
- `bd prime` succeeded but subsequent `bd` commands fail or return empty.
  (`bd prime` reads local files, NOT the database — its success does NOT
  prove the DB connection is live.)

**Recovery steps**:

1. Check the current topic:
   ```bash
   timvisher_bd_topics current
   ```
2. Re-set the topic — **always do this step**, even if step 1 shows a
   topic is already set. A set topic does not mean the DB connection is
   live; re-setting fixes stale connections:
   ```bash
   timvisher_bd_topics set <topic>
   ```
3. Retry the original `bd` command.
4. If still failing, restart the topic's Dolt server and re-set:
   ```bash
   bd dolt stop --force
   bd dolt start
   timvisher_bd_topics set <topic>
   ```
5. If STILL failing after steps 1-4, **ask the user**. Do not improvise
   further. Do not try `bd init`, `bd doctor --fix`, or any other approach.

## Setup and topic selection

- Use **bd (beads)** for issue tracking only if the repo root contains a
  `.beads` directory or `.timvisher_bd_topics` directory. If you're not in
  a git repo, do not use bd.
- **IMPORTANT**: `.beads` is always a directory. NEVER try to read it as a
  file (`cat .beads`), check whether it is a file vs directory, or inspect
  its contents. Just check for existence and use `bd` /
  `timvisher_bd_topics` commands.
- Before doing any work, make sure beads is live in the current worktree.
  Check the active topic with `timvisher_bd_topics current` (non-zero exit
  means no topic is set). If none is set, list topics and offer to set one.
  `ls` supports `--all` to include deactivated topics and prefixes to narrow
  results; output marks `(current)` and `(deactivated)`:
  ```bash
  timvisher_bd_topics current
  timvisher_bd_topics ls --all
  timvisher_bd_topics set <topic>
  ```
- Run `bd prime` for workflow context, or install hooks with
  `bd hooks install`. If `bd prime` says to `git push`, ignore that
  instruction and ask the user to push instead.
- **Validate DB connection**: Immediately after `bd prime`, run `bd list`
  (no filters). If it returns empty or errors, the DB connection is broken —
  run the recovery steps before doing anything else. Do NOT proceed to
  `bd ready`, `bd create`, or any other `bd` command until `bd list`
  returns results. (`bd prime` reads local files, not the DB, so its
  success does not prove the DB is working.)

## Context alignment

- Always treat the active bead as the primary objective.
  If you start mid-bead, find the in-progress issue and make the session goal
  a sub-step of that bead. If a user request does not fit the active bead,
  ask to re-scope or create/claim a new bead before coding.

## Multi-agent coordination

- Check `bd list --status=in_progress` before claiming work.
- Use `bd show <id>` to confirm assignee; avoid claiming work owned by another agent.
- When starting, set assignee and status in one step: `bd update <id> --status=in_progress --assignee <UUID>`.
  Use a UUID-only assignee (no agent name or date), preserve it across compactions, and reuse it when another agent takes over.
- On session close, clear the assignee (for example: `bd update <id> --assignee ""`) so other sessions know the work is free.
- Optional: report agent state with `bd agent state <UUID> working` for monitoring.

## Quick reference

```bash
bd ready
bd list --status=in_progress
bd create "Title" --type task --priority 2
bd close <id>
bd sync
```

## timvisher_bd_topics commands

```bash
timvisher_bd_topics current           # Show current topic (non-zero = none set)
timvisher_bd_topics ls [--all]        # List topics (--all includes deactivated)
timvisher_bd_topics set <topic>       # Set topic + write redirect
timvisher_bd_topics new <topic>       # Create new topic (brand-new projects only)
timvisher_bd_topics deactivate <topic>  # Hide topic from ls/set
timvisher_bd_topics activate <topic>    # Re-enable deactivated topic
bd dolt start                         # Start the current topic's Dolt server
bd dolt stop                          # Stop the current topic's Dolt server
bd dolt status                        # Check the current topic's server status
```

## Session completion

Work is not done until all changes are committed, the worktree is clean,
and `bd sync` has succeeded.
