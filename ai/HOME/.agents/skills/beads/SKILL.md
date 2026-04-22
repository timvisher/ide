---
name: beads
description: Beads (bd) issue-tracking workflow, topic selection, and session completion rules.
---

# Beads workflow

## When to use
- Working in a repo with a `.beads` directory or `.timvisher_bd_topics` directory.
- Managing issue tracking, topic selection, or session completion.

## Primary entrypoints

`bd` is self-documenting. Use these as your first stop for any question
about commands or workflow:

- **`bd --help`** — full command index. Use it whenever you need to find
  the right `bd` subcommand. Don't guess command names from memory.
- **`bd <command> --help`** — flags and usage for any subcommand.
- **`bd prime`** — AI-optimized workflow context (essential commands,
  workflows, session-close protocol). Run it at session start and after
  any compaction/clear.

This skill exists only to cover what `bd --help` and `bd prime` do NOT:
topic management, recovery from broken DB connections, multi-agent
coordination, and the things you must never do.

## Bootstrapping a session

1. Check that beads is live in the worktree: look for a `.beads`
   directory or `.timvisher_bd_topics` directory at the repo root. If
   neither exists and the user has not asked to set one up, do not use
   `bd`.
2. Check the active topic with `timvisher_bd_topics current` (non-zero
   exit means no topic is set). If none is set, run
   `timvisher_bd_topics ls [--all]` and offer to set one with
   `timvisher_bd_topics set <topic>`.
3. Run `bd prime` for workflow context. If it tells you to `git push`,
   ignore that part and ask the user to push instead.
4. **Validate the DB connection**: immediately after `bd prime`, run
   `bd list` (no filters). If it errors, run recovery (below) before
   any other `bd` command. If it returns empty, treat that as
   suspicious only when you have reason to believe issues exist (a
   fresh topic legitimately has none); otherwise proceed and revisit
   if later commands behave oddly. `bd prime` reads local files, not
   the DB, so its success does not prove the DB is working.

## `.beads` is opaque
- `.beads` is always a directory. NEVER read it as a file, check file vs
  directory, or inspect its contents (no `cat .beads`, no `ls .beads/`).
- All state is managed by per-topic Dolt servers (auto-started by `bd`,
  idle-stopped after 30 min). Interact only via `bd` and
  `timvisher_bd_topics`.

## NEVER do these things
- **NEVER run `bd init` or `bd init --force`** as a recovery step. These
  are for brand-new repos only; in worktrees they always fail. The fix
  for "issue_prefix missing" or "database not initialized" is
  `timvisher_bd_topics set <topic>`, NOT `bd init`.
- **NEVER run `bd doctor --fix --yes`** without user approval.
- **NEVER use `bd edit`** — it opens `$EDITOR` and blocks the agent. Use
  `bd update <id> --title/--description/--notes/--design` instead.
- **NEVER manipulate `.beads/` contents directly** (no `cat`, `ls`,
  `rm`, `mkdir` inside `.beads/`).
- **NEVER fall back to TodoWrite or markdown TODO lists** when `bd`
  fails. Fix `bd` using recovery, or ask the user.

## Recovery: bd fails OR returns suspicious results

Triggers — run recovery if ANY of these happen:
- Explicit DB errors: "table not found", "issue_prefix config is
  missing", "database not initialized", connection refused, etc.
- **Silent empty results**: `bd list` returns nothing, `bd ready` says
  "No open issues", or any `bd` query returns empty when you have reason
  to believe issues exist.
- `bd prime` succeeded but subsequent `bd` commands fail or return
  empty.

Recovery steps:

1. `timvisher_bd_topics current` — check current topic.
2. `timvisher_bd_topics set <topic>` — re-set it. **Do this even if
   step 1 shows a topic is set.** A set topic does NOT mean the DB
   connection is live; re-setting fixes stale connections.
3. Retry the original `bd` command.
4. If still failing, restart the topic's Dolt server:
   ```bash
   bd dolt stop --force
   bd dolt start
   timvisher_bd_topics set <topic>
   ```
5. If STILL failing after steps 1–4, **ask the user**. Do not improvise.
   Do not try `bd init`, `bd doctor --fix`, or any other approach.

## Context alignment

Treat the active in-progress bead as the primary objective. If you start
mid-bead, find the in-progress issue and make the session goal a
sub-step of it. If a user request does not fit the active bead, ask to
re-scope or create/claim a new bead before coding.

## Multi-agent coordination

- Check `bd list --status=in_progress` before claiming work.
- Use `bd show <id>` to confirm assignee; avoid claiming work owned by
  another agent.
- When starting, set assignee and status in one step:
  `bd update <id> --status=in_progress --assignee <UUID>`. Use a
  UUID-only assignee (no agent name or date), preserve it across
  compactions, and reuse it when another agent takes over.
- On session close, clear the assignee
  (`bd update <id> --assignee ""`) so other sessions know the work is
  free.

## `timvisher_bd_topics` quick reference

```bash
timvisher_bd_topics current             # Show current topic (non-zero = none set)
timvisher_bd_topics ls [--all]          # List topics (--all includes deactivated)
timvisher_bd_topics set <topic>         # Set topic + write redirect
timvisher_bd_topics new <topic>         # Create new topic (brand-new projects only)
timvisher_bd_topics deactivate <topic>  # Hide topic from ls/set
timvisher_bd_topics activate <topic>    # Re-enable deactivated topic
```

For everything else, run `bd --help` or `bd <command> --help`.
