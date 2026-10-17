---
name: session-handoff
description: Hand a live agent session off to a new context (another topic, subtopic, worktree or directory) so Tim can resume it there. Produces a copy-the-session prompt for the new context's agent, which then produces the resume prompt.
---

# Session handoff

## When to use
- Tim asks for a handoff, bootstrap or resume prompt so this session (or
  another one) can continue somewhere else.
- Work outgrew its home: a new topic or subtopic was created, or the work
  belongs in a worktree.
- Tim asks to "move", "copy" or "resume this session there".

For handing a *task* to another context's existing agent, with no session
carried over, write an ordinary handoff prompt instead (see `make-prompt`).

## The two-step handoff

1. **This session** writes a prompt for a fresh agent in the new context.
   That agent copies the session in (if needed) and writes step 2.
2. **The new context's agent** writes the resume prompt. Tim resumes the
   copied session there and pastes it in.

Never tell Tim to kill, close or detach the source session first. Expect
it to be live but idle. The copying agent waits for the transcript to stay
quiet and copies it. Tim simply stops using the old buffer.

## Step 1: decide whether a copy is needed

Claude Code finds sessions by working directory. Its project dir is the
cwd with every character that isn't a letter or digit replaced by `-`:

```bash
claude_project_dir() {
  printf '%s/.claude/projects/%s\n' "$HOME" "${1//[^a-zA-Z0-9]/-}"
}
```

- **Same cwd** (same project dir): no copy. Give the resume prompt
  (step 3) directly.
- **Different cwd:** the session must be copied. Write the copy prompt
  (step 2).

Find the session ID with `grep -l` for a phrase from Tim's **latest**
message, over the project dir's `*.jsonl` files. Two traps:

- **A resumed session can continue in a new file under a new ID**, which
  carries the whole history. The ID it started under (and the one in
  older agent-shell transcript headers) then goes stale. Always copy the
  file holding the latest turn.
- **The newest file may be a different, concurrent session.** Match on
  content, not mtime.

## Step 2: the copy prompt (for the new context's agent)

Tell Tim the command that starts the agent there
(`cd <new cwd> && claude`), then give a prompt that has the agent:

1. **Wait for idle.** Poll the source `.jsonl`'s mtime until it has been
   unchanged for 45 seconds. Recent activity is fine; just keep waiting.
   Give up after 10 minutes and report, without telling Tim to stop the
   source.
   ```bash
   src=<source project dir>/<id>.jsonl
   while (( $(date +%s) - $(date -r "$src" +%s) < 45 ))
   do
     sleep 5
   done
   ```
2. **Copy, never move:** `cp -p` the `<id>.jsonl` and the sibling `<id>/`
   directory (`subagents/`, `tool-results/`) into the new project dir.
   Create it if it's missing. Verify with `cmp`. If the source changed
   during the copy, wait for idle again and recopy.
3. **Copy the agent-shell transcripts** whose header carries this
   `Session ID:` from `<old cwd>/.agent-shell/transcripts/` into
   `<new cwd>/.agent-shell/transcripts/`, keeping their names. Leave the
   originals in place.
4. **Copy or link related files** this session produced or relied on
   (topic notes, `references/`, `x.` scratch files). Name each one
   explicitly; never "whatever looks relevant".
5. **Leave beads where they are.** Report which topic holds the session's
   beads, and ask Tim before moving any.
6. **Write the resume prompt** (step 3), adapted to what it found, and
   report what it copied, with sizes and `cmp` results.

Include the step 3 content in the copy prompt, so the new agent can adapt
it instead of reconstructing it.

## Step 3: the resume prompt (pasted into the resumed session)

The resumed session already holds its whole history, so keep this short:

- **Where it is now:** the new cwd, topic and beads location, and that its
  transcript was copied there, so the old paths in its history are stale.
- **What changed since it last ran:** files copied, beads moved or not,
  decisions Tim made in between.
- **What's next:** the open question or bead to pick up, in one or two
  lines. Don't re-summarize the design; it's in the history.
- **How to resume:** `cd <new cwd> && claude --resume <id>`, or the
  agent-shell equivalent from that directory.

## Rules
- Use absolute paths everywhere. Quote paths with spaces.
- One copy-prompt per handoff, delivered as a fenced block in chat. Never
  write prompts to repo files (`make-prompt`).
- If Tim asks, copy the prompt to the clipboard (`pbcopy`) or open the new
  context in a terminal (`worktree` skill, `ntmux3`).
