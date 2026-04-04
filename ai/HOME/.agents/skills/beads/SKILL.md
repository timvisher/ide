---
name: beads
description: Beads (bd) issue-tracking workflow, topic selection, and session completion rules.
---

# Beads workflow

## When to use
- Working in a repo with a `.beads` directory or `.timvisher_bd_topics` directory.
- Managing issue tracking, topic selection, or session completion.

## Important: `.beads` is a directory — treat it as opaque
- `.beads` is always a directory. NEVER read it as a file, check file vs
  directory, or inspect its contents (no `cat .beads`, no `ls .beads/`).
- All database state is managed by per-topic Dolt servers (auto-started
  by `bd`). Use only `bd` and `timvisher_bd_topics` commands to interact
  with beads.

## NEVER do these things
- **NEVER run `bd init` or `bd init --force`** as a recovery step. These are
  for brand-new repos only. In worktrees they will always fail. If you see
  "issue_prefix config is missing" or "database not initialized", the fix is
  `timvisher_bd_topics set <topic>`, NOT `bd init`.
- **NEVER run `bd doctor --fix --yes`** without user approval.
- **NEVER manipulate `.beads/` contents directly** (no `cat`, `ls`, `rm`,
  `mkdir` inside `.beads/`).
- **NEVER fall back to TodoWrite** when bd fails. Fix bd or ask the user.

## Architecture (why things break)
- Each repo worktree has `.beads/redirect` pointing to a topic directory
  under `~/Documents/datadog/projects/`.
- Each topic has its own `.beads/` directory with a standalone Dolt server
  on a hash-derived port (auto-started by `bd`, idle-stopped after 30 min).
- `timvisher_bd_topics set <topic>` writes the redirect. If the redirect
  is stale, `bd` commands will fail with confusing errors like "table not
  found" or "prefix missing".
- Per-topic servers are managed by `bd dolt start|stop|status` directly
  (the worktree redirect routes to the correct topic automatically).

## Recovery: when bd commands fail OR return suspicious results
If any `bd` command fails with database errors ("table not found",
"issue_prefix missing", "database not initialized", connection errors)
**OR returns unexpectedly empty results** (e.g., `bd list` shows nothing
when you know issues exist, or `bd ready` returns empty right after
`bd prime` showed a valid redirect), treat it as a **broken DB connection**:

1. `timvisher_bd_topics current` — check if a topic is set
2. `timvisher_bd_topics set <topic>` — re-set it (rewrites redirect,
   reconnects DB). **Do this even if step 1 shows a topic is set.** A set
   topic does NOT mean the DB connection is live; re-setting fixes stale
   connections.
3. Retry the original `bd` command.
4. If still failing, restart the topic's Dolt server:
   ```bash
   bd dolt stop --force
   bd dolt start
   timvisher_bd_topics set <topic>
   ```
5. If STILL failing after steps 1-4, **ask the user**. Do not improvise.

**IMPORTANT**: `bd prime` can succeed while the DB connection is broken
(`bd prime` reads local redirect files, not the DB). Never trust
`bd prime` success as proof that the DB is working.

## Workflow
- Confirm beads is live; set a topic if needed.
- If the repo lacks `.beads`/`.timvisher_bd_topics`, you may still run
  `timvisher_bd_topics set <topic>` to initialize topic tracking if the user
  directs you to; this is the supported bootstrap path.
- Run `bd prime` for workflow context or install hooks. If `bd prime` says to
  `git push`, ignore that part and ask the user to push instead.
- **Validate DB connection**: Immediately after `bd prime`, run `bd list`
  (no filters). If it returns empty or errors, the DB connection is broken —
  run recovery before doing anything else. Do NOT proceed to `bd ready`,
  `bd create`, or any other `bd` command until `bd list` returns results.
- Identify the active bead (in_progress) and treat it as the primary context; session tasks are sub-steps of that bead.
- Multi-agent coordination: check for existing in_progress issues and assignees before claiming work; set assignee when starting using a UUID-only identity (no agent name or date), preserve it across compactions so another agent can resume it, and clear the assignee on session close.
- Use bd for issue tracking and session completion.

## References
- See references/beads.md for commands, required steps, and full
  troubleshooting details.
