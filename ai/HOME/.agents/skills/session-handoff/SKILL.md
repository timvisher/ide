---
name: session-handoff
description: Hand a live agent session off to a new context (another topic, subtopic, worktree or directory) so Tim can resume it there. Starts an agent in the new context with timvisher_emacs that copies the session in and sends the resumed session its resume prompt.
---

# Session handoff

## When to use
- Tim asks for a handoff, bootstrap or resume prompt so this session (or
  another one) can continue somewhere else.
- Work outgrew its home: a new topic or subtopic was created, or the work
  belongs in a worktree.
- Tim asks to "move", "copy" or "resume this session there".

For handing a *task* to another context's agent, with no session carried
over, send it an ordinary message instead (`agent-shell-sessions`).

Every `timvisher_emacs agent-shell` command here is covered in the
`agent-shell-sessions` skill. Read it first.

## How it goes

1. **This session** finds itself, writes the copy prompt, and starts a
   copying agent in the new context with that prompt.
2. **The copying agent** waits for this session to go idle, copies it
   in, and writes the resume prompt.
3. **Tim** resumes the copy in the new context's Emacs. That is the only
   manual step, because no tool resumes a session by id yet.
4. **The copying agent** sends the resume prompt to the resumed session.

Never tell Tim to kill, close or detach the source session. It stays
live and idle; Tim just stops using the old buffer.

## Step 1: find this session

Get this session's name from `ListAgents`, then its row from
`timvisher_emacs agent-shell ls`:

```bash
timvisher_emacs agent-shell ls | jq --arg name "<name>" '.sessions[] | select(.name == $name)'
```

The row gives `session_id`, `cwd` (with a trailing `/`) and
`emacs_pid`. Use this `session_id` rather than one from older
transcript headers: a resumed session can carry on under a new id, and
the live one is the one to copy. Check that the `<session_id>.jsonl` file exists in this cwd's
Claude project dir. That dir is the cwd with every character that
isn't a letter or digit replaced by `-`, trailing `/` dropped first:

```bash
claude_project_dir() {
  local cwd=${1%/}
  printf '%s/.claude/projects/%s\n' "$HOME" "${cwd//[^a-zA-Z0-9]/-}"
}
```

If the new cwd maps to the same project dir, nothing needs copying.
Give Tim the resume prompt (step 4) directly.

## Step 2: start the copying agent

Write the copy prompt (step 3) to `/tmp/x.handoff-<session name>`, then
start the agent in the new context's Emacs:

- **Existing worktree:**
  ```bash
  timvisher_emacs agent-shell start --emacs "$(ntmux3 get-editor-pid <path>)" \
    --prompt-file /tmp/x.handoff-<session name>
  ```
- **New worktree:** create it with the `worktree` skill, passing the
  prompt through `TIMVISHER_NTMUX3_AI_AGENT_INITIAL_PROMPT`.
- **Directory with no Emacs serving it:** ask Tim to open an
  agent-shell there, then `timvisher_emacs agent-shell send` the prompt
  file to that agent once it appears in `agent-shell ls`.

The new shell works in its Emacs's directory, so check the new row's
`cwd` in `agent-shell ls`. Tell Tim the copying agent's name and ref,
then end your turn: the copying agent waits for you to go idle.

## Step 3: the copy prompt

Open with `From the <who> agent (session <name> [<ref>])`. Give the
source `session_id`, its cwd and project dir, the new cwd and project
dir, and have the agent:

1. **Wait for idle.** Poll `timvisher_emacs agent-shell ls` until the
   source row's `status` is `ready`, then until the source `.jsonl` has
   gone 45 seconds without changing. Give up after 10 minutes and report
   back, without telling Tim to stop the source.
2. **Copy, never move:** `cp -p` the `<id>.jsonl` and the sibling `<id>/`
   directory (`subagents/`, `tool-results/`) into the new project dir.
   Create the dir if it's missing. Verify with `cmp`. If the source
   changed during the copy, wait for idle again and recopy.
3. **Copy the agent-shell transcripts** whose header carries this
   `Session ID:` from `<old cwd>/.agent-shell/transcripts/` into
   `<new cwd>/.agent-shell/transcripts/`, keeping their names. Leave the
   originals in place.
4. **Copy or link related files** this session produced or relied on
   (topic notes, `references/`, `x.` scratch files). Name each one
   explicitly, never "whatever looks relevant".
5. **Leave beads where they are.** Report which topic holds the
   session's beads, and ask Tim before moving any.
6. **Write the resume prompt** (step 4), adapted to what it found, to
   `/tmp/x.resume-<id>`. Report what it copied, with sizes and `cmp`
   results, and ask Tim to resume `<id>` in this Emacs
   (`M-x agent-shell-resume-session`).
7. **Send the resume prompt.** Poll `agent-shell ls` for up to 10
   minutes for a row in the new cwd with the copied `session_id`. Then
   `timvisher_emacs agent-shell send "<name> [<ref>]" /tmp/x.resume-<id>`
   using that row's name and ref. The full id won't work here: it
   matches the old shell too, so `send` fails as ambiguous. If no row
   appears, or the resumed session got a new id, wait for Tim to say
   which session it is.

Put the step 4 content in the copy prompt, so the copying agent can
adapt it instead of reconstructing it.

## Step 4: the resume prompt

The resumed session already holds its whole history, so keep this short:

- **Who it's from:** open with `From the <who> agent (session <name> [<ref>])`.
- **Where it is now:** the new cwd, topic and beads location, and that
  its transcript was copied there, so the old paths in its history are
  stale.
- **What changed since it last ran:** files copied, beads moved or not,
  decisions Tim made in between.
- **What's next:** the open question or bead to pick up, in one or two
  lines. Don't re-summarize the design; it's in the history.

## Rules
- Use absolute paths everywhere. Quote paths with spaces.
- Prompts go in `/tmp/x.*` files and are delivered with
  `timvisher_emacs agent-shell start` or `send`. Never write them to
  repo files (`make-prompt`).
- Never hand-build `emacsclient --eval` forms to start, message or
  resume a shell (`agent-shell-sessions`).
