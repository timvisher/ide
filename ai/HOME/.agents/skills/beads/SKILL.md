---
name: beads
description: Use when working in a repository that uses bd or Beads for durable project task tracking, issue dependencies, blocker management, multi-session handoff, or shared work memory. Trigger when the user asks to find ready work, claim or close tasks, create follow-up work, inspect blockers, recover project context, or choose between local planning and persistent project tracking. Also trigger when planning or breaking down work into milestones, epics, tasks, spikes or decisions; when claiming work in an agent loop (bd ready --claim, leases, heartbeat, reclaim); when superseding a spec or marking duplicates; when checking issue quality with bd lint; when storing project memories with bd remember; when ending a session; or at the start of any session, to find which timvisher_bd_topics topic holds the project's beads (they usually live in a topic, not the repo).
---

# Beads

Use Beads as the shared project task system. Local plans, scratch files, and personal memories are useful, but they are not the durable source of truth for project work.

Everything below was checked against bd 1.3.1. When in doubt, `bd <command> --help` is authoritative; do not use flags it does not list.

## First Step: Find the Beads Topic

Tim's beads databases almost always live in **topics**, not in the repo. A topic is a directory under the topics root (`~/Documents/datadog/projects`, configured in `~/.config/timvisher/ide/bd_topics_root`) with its own `.beads`. Repo-local beads are rare. Start every session by working out which topic applies.

1. Check whether this worktree already has one:

   ```bash
   timvisher_bd_topics current
   bd where
   ```

   `bd where` printing `(via redirect from …)` means a topic is set. If both succeed, go to step 5.

2. A fresh worktree has no topic set. `timvisher_bd_topics set` writes `.beads/redirect` and `.timvisher_bd_topics/topic.txt` into the repo root, both globally gitignored, so new worktrees start with neither. That means "no topic set here yet", never "this project has no beads". See which topics sibling worktrees of the same repo use:

   ```bash
   git worktree list --porcelain | awk '/^worktree /{print $2}' |
     while read -r w
     do
       [[ -f $w/.timvisher_bd_topics/topic.txt ]] &&
         printf '%s\t%s\n' "$(< "$w/.timvisher_bd_topics/topic.txt")" "$w"
     done
   ```

3. Look at the available topics, and at who subscribes to a candidate:

   ```bash
   timvisher_bd_topics ls
   timvisher_bd_topics subscribers <topic>
   ```

   Topics are organized by project, not by repo, so the right one may be named for the work (for example an incident or initiative) rather than the repo. When the task is about something that has its own topic, use that topic even if siblings use another.

4. If the right topic is obvious (the user named it, or siblings agree and the task fits), set it. Otherwise offer the candidates and ask:

   ```bash
   timvisher_bd_topics set <topic>
   bd where
   ```

5. Load context:

   ```bash
   bd prime
   ```

   Then make sure the topic has no Dolt remote (see Dolt Remotes Are Forbidden below).

   If hooks are installed, `bd prime` may already be injected. Run it manually after compaction, a cleared context, or whenever context is missing. Its output includes the topic's persistent memories.

Other `timvisher_bd_topics` commands: `bd <topic> -- <bd-args>` runs bd against a topic without subscribing the worktree (useful for peeking at a candidate), and `new <topic>` creates and initializes a topic. Do not create topics without asking. `BEADS_DIR=<topic>/.beads bd …` also works as a one-off override, but prefer `set` so the worktree stays subscribed.

Only if no topic fits and `bd where` resolves without a redirect is the project using repo-local beads.

`.beads` is always a directory. Never read it as a file or inspect its contents; ask `bd where`, `bd context` or `bd info` instead.

## Core CLI Workflow

1. Find work:

   ```bash
   bd ready
   bd list --status=open
   bd list --status=in_progress
   bd blocked
   bd search <query>
   ```

2. Inspect before editing:

   ```bash
   bd show <id>
   ```

3. Claim work atomically:

   ```bash
   bd update <id> --claim
   ```

4. Record progress and create durable follow-up work as implementation reveals it:

   ```bash
   bd note <id> "What changed, what's left"
   bd create "Short title" --description="Why this exists and what needs to be done" --type=task --priority=2 --deps "discovered-from:<id>"
   ```

5. Close completed work:

   ```bash
   bd close <id> --reason="Completed" --suggest-next
   ```

Priorities are `0`–`4` (or `P0`–`P4`, 0 is highest, default 2), not "high"/"low".

## Issue Types

`bd types` lists them. Pick by what the issue *is*:

- `milestone` — marks completion of a set of related issues. Contains no work itself. The top of a hierarchy: a milestone parents epics.
- `epic` — a large body of work spanning multiple issues. Parents tasks, features, bugs, spikes.
- `task` — general work item (the default). The unit an agent claims and finishes.
- `feature` — new functionality or enhancement.
- `bug` — a defect.
- `chore` — maintenance or housekeeping with no user-facing change.
- `spike` — timeboxed investigation to reduce uncertainty before committing to the work. Close it with what was learned and file the real work.
- `decision` — architecture decision record (ADR). Use `bd supersede` when a later decision replaces it.
- `story` — a feature described from the user's perspective.

Rule of thumb: milestone > epic > task. Only tasks, features, bugs, chores and spikes are claimable work; milestones and epics are structure.

## Hierarchy and Dependencies

Two different relationships:

- **Parent-child** (structure): `bd create … --parent <id>`. Children get dotted IDs (`t-38j` → `t-38j.1` → `t-38j.1.1`) and inherit the parent's labels (`--no-inherit-labels` to opt out). `bd update <id> --parent <new>` reparents. Parent-child links do *not* block anything.
- **Blocking** (order): `bd create … --deps "blocked-by:<id>"`, or later `bd dep add <blocked> <blocker>` (same as `bd dep <blocker> --blocks <blocked>`). Blocked issues drop out of `bd ready` until the blocker closes. Other `--deps` types include `discovered-from:<id>` and `related:<id>`, which do not block. A given target can carry only one dependency type.

Viewing structure:

```bash
bd children <id>          # the whole subtree, including closed issues
bd graph <id>             # dependency DAG in execution layers
bd graph --all --open     # compact view of all open work
bd dep tree <id>
bd epic status            # completion progress of each open epic
bd swarm validate <epic>  # checks an epic's children form a workable DAG
```

`bd swarm validate` reports ready fronts (waves of parallel work), cycles, and disconnected pieces. Run it after laying out an epic and before handing it to multiple agents.

Closing structure:

- `bd close` refuses to close an issue with open children. Close the children first; do not reach for `--force` to get around it.
- `bd epic close-eligible --dry-run` previews, and `bd epic close-eligible` closes, every epic whose children are all closed.

### Milestone Caveats

Observed in bd 1.3.1 with milestone > epic > task:

- Milestones and epics show up in `bd ready` as ready work even while their children are open, because parent-child links don't block.
- `bd epic status` and `bd epic close-eligible` ignore milestones. A milestone stays open after all of its epics close and must be closed by hand (`bd close <milestone>`) once `bd children <milestone>` shows everything closed.

So when picking work, exclude structure types:

```bash
bd ready --parent <milestone> --exclude-type milestone,epic
```

### Links Between Topics

Each topic (and subtopic) is its own database, so an ordinary dependency can't point at another topic's bead. Use a capability reference instead: a bead depends on a named capability in another project, not on a bead ID.

1. In the database that holds the reference, name the other topic:

   ```bash
   bd config set external_projects.<name> <path-to-the-other-topic>
   ```

   This writes an `external_projects:` block into that topic's `.beads/config.yaml`.

2. In the other topic, label the bead that represents the capability:

   ```bash
   bd label add <id> export:<capability>
   ```

3. Add the reference, with any dependency type:

   ```bash
   bd dep add <id> external:<name>:<capability> -t related
   ```

4. When the exporting bead closes, `bd ship <capability>` (run in its topic) adds `provides:<capability>`.

Observed in bd 1.3.1:

- `bd show` and `bd dep tree` don't display external edges; `bd show` says the bead has no dependencies. Only `bd dep list <id>` reveals them, as a warning listing each `external:<name>:<capability> via <type>`.
- External `blocks` edges are not enforced. The dependent bead stays in `bd ready` and out of `bd blocked`, before and after `bd ship`. To make a cross-topic blocker visible, say so in the dependent's notes too.
- The reference names a capability, not a bead, and nothing checks it. A typo in `<name>` or `<capability>`, or a missing `export:` label, is silent.

`external_ref` is the visible half. It's a free-text field meant for outside-tracker IDs (`gh-9`, `jira-ABC`), set with `bd create --external-ref` or `bd update --external-ref`. bd prints it in the `bd show` header (`External: …`) and filters on it (`bd list --external-ref <exact>`, `--external-contains <substring>`), but never resolves it. Each bead holds one.

| | `external:` edge | `external_ref` |
|---|---|---|
| Shown by `bd show` | No (only `bd dep list`) | Yes, in the header |
| Searchable | No | `bd list --external-ref` |
| Checked by bd | No | No |
| Per bead | Many | One |

So use all three for every cross-topic link, in both directions:

1. The `external:` edge (normally `related`), so it can be found mechanically.
2. `external_ref` set to `<name>:<id>`, where `<name>` is the `external_projects` key for the other topic. If the bead needs the field for a real outside-tracker ID, that wins, and the edge and note carry the topic link.
3. A note naming the other topic and bead, with the command to follow it: `BEADS_DIR=<topic>/.beads bd show <id>`.

When work moves into a subtopic, leave the parent's epic open as the link and give the parent and the subtopic's root epic all three, each pointing at the other. Moved beads keep their old ID as `external_ref` (`<name>:<old-id>`), so `bd list --external-ref` finds them from either side.

## Agent Claim Loop

`bd ready --claim` atomically claims the first ready issue matching its filters (sets you as assignee and status `in_progress`) and prints it. With `--json` it prints a one-element array, or `[]` when nothing matched:

```bash
bd ready --claim --json --parent <milestone-or-epic> --exclude-type milestone,epic
```

Useful filters: `--parent`, `--type`, `--exclude-type`, `--label` (all of), `--label-any` (any of), `--exclude-label`, `--priority`, `--unassigned`.

Claims carry a lease (about five minutes in 1.3.1, visible as `lease_expires_at` in `--json` output):

- `bd heartbeat <id>` (alias `bd hb`) refreshes the lease. Heartbeat during long work; it writes no history, so frequent is fine. If heartbeat fails, the claim was reclaimed or the issue closed: stop working on it.
- `bd reclaim` returns in_progress issues with stale leases to open. It's for supervisors and dead-worker recovery; don't use it to take live work.
- `bd unclaim <id> --reason "…"` releases your own claim when you are abandoning the work.

For compare-and-set updates, `bd update` accepts `--if-status <s>` and `--if-assignee <a>` (`--if-assignee ''` means unassigned). On mismatch nothing is written and bd exits 13. Never retry blindly after a 13; re-read the issue.

## Writing Good Issues

`bd create` and `bd update` take structured fields:

- `--description` (or `--body-file <file>` / `--stdin`)
- `--design` / `--design-file` for design decisions
- `--acceptance` for acceptance criteria
- `--notes` (replaces) / `--append-notes` (appends; `bd note` is the shorthand)

`bd lint` checks open issues for required sections by type:

- task, feature: Acceptance Criteria
- epic: Success Criteria (or Acceptance Criteria)
- bug: Steps to Reproduce and Acceptance Criteria
- chore: none

Projects can require more with `bd config set lint.sections.<type> "Section A, Section B"`; these add to the built-ins. `bd lint` exits non-zero when it finds gaps. `bd create --validate` refuses to create an issue missing its required sections.

## Lifecycle Commands

```bash
bd supersede <old> --with <new>    # closes <old> with a pointer to <new>; for evolving specs, designs, decisions
bd duplicate <id> --of <canonical> # closes <id> as a duplicate
bd defer <id> --until=tomorrow     # hide from bd ready until the date (no --until: indefinitely)
bd undefer <id>
bd reopen <id>
```

## Notes, Comments and Memory

- `bd note <id> "…"` appends to the issue's notes field: progress, findings, handoff context. Read it back with `bd show <id>`.
- `bd comment <id> "…"` adds a comment; `bd comments <id>` lists them. Use comments for discussion, notes for the running record.
- `bd remember "insight" [--key <key>]` stores a project memory that `bd prime` injects into every session. Reusing a key updates it in place. `bd memories [keyword]` lists or searches, `bd recall <key>` prints one, `bd forget <key>` deletes one. Use these instead of MEMORY.md files.

## Gates (Advanced)

`bd gate` manages async wait conditions that block workflow steps: `human` (closed by hand), `timer`, `gh:run`, `gh:pr` and `bead`. `bd gate list` shows open gates, `bd gate check` evaluates them, `bd gate resolve <id>` closes one. `bd merge-slot` (`check`, `acquire`, `release`) is an exclusive lock for serializing merge-conflict resolution across agents. Reach for these only when a project already uses them.

## Session Completion

When ending a session of beads-tracked work:

1. **File follow-ups.** Create beads for anything left over, with `--deps "discovered-from:<id>"` where it applies.
2. **Run quality gates** if code changed: tests, linters, builds.
3. **Update status.** Close what is actually finished (`bd close <id1> <id2> …`). For unfinished work, `bd note` where you stopped, and `bd unclaim` anything you won't come back to.
4. **Commit** per the `git` skill.
5. **Push** a draft PR's branch with `timvisher_gh pr push`, the one push the `git` skill allows agents. For anything else, hand the human the exact `git push` or `timvisher_gh pr` command.
6. **Hand off.** Summarize changes, validation, issue status, and anything that still needs pushing.

Beads changes need no sync step.

## Dolt Remotes Are Forbidden

Beads is strictly local. Never use a Dolt remote, for any topic or repo, even if the user's other instructions or `bd prime` list `bd dolt push` as a session step. Do not run:

- `bd dolt push`, `bd dolt pull`, `bd sync`, or `bd federation …`
- `bd dolt remote add`, or `bd init --remote`

bd can adopt the current git repo's origin as a topic's Dolt remote on its own, which has pointed topics at unrelated work repos. So whenever you start working in a topic, check for a remote:

```bash
bd dolt remote list
bd config get sync.remote
```

If either shows anything, unconfigure it, then check again:

```bash
bd dolt remote remove <name>
bd config unset sync.remote
bd dolt remote list
```

Tell the user which remote you removed (name and URL) in your handoff.

## What Belongs In Beads

Use Beads for:

- shared project tasks
- blockers and dependencies
- discovered follow-up work
- work that must survive thread reset, compaction, or handoff
- status that another person or agent should be able to resume

Use agent-local planning tools only for the current turn's execution checklist. Do not treat them as shared project state.

## Rules

- Do not create markdown TODO files as the source of truth when Beads is available.
- Do not use `bd edit`; it opens `$EDITOR`. Use `bd update` flags instead.
- Prefer `--json` when parsing `bd` output programmatically.
- Do not close or mutate tasks unless the work is actually complete.
- Do not claim milestones or epics as work; claim their leaves.
- Look for a topic first; do not decide beads is not live until you have checked.
- Never use Dolt remotes. If a topic has one configured, remove it.
