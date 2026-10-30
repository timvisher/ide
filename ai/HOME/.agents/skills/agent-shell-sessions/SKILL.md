---
name: agent-shell-sessions
description: Message, find, start, and recover other agent-shell sessions (Claude Code or Codex running in Emacs) with timvisher_emacs. Use whenever you need to put a message into another agent session's prompt (named by its ListAgents name or ref, or its session id), find which Emacs hosts a session, start a new agent-shell with a first prompt, check whether a session is wedged, or recover a wedged one. Never hand-build emacsclient --eval forms for any of this.
---

# Agent-shell sessions

## When to use
- Handing a message, request or handoff to another agent session.
- Spawning a new agent in a worktree's Emacs with a first prompt.
- A session looks stuck: busy for a long time with nothing happening.

## Naming a session

Every `<session>` below takes any of the forms `ListAgents` shows:
a name (`datadog-a7`), a ref (`cc09f8`), both as printed
(`"datadog-a7 [cc09f8]"`), or a full session id. Names and refs come
from Claude Code's session files, so a Codex session has neither:
reach it by its full session id. An ambiguous name or short ref fails
with `timvisher_emacs_ambiguous_session`, listing each match.

## Sending a message

1. Write the message to a file outside any worktree (`/tmp/x.<name>`)
   so writing it takes no worktree lock.
2. Start it with a `From the <who> agent (session <name or id>)` line.
   Text you send shows up as though Tim typed it.
3. Send it:

   ```bash
   timvisher_emacs session send <session> /tmp/x.message
   ```

It prints `submitted` when the shell was idle, or `queued` when it
was busy or Tim had something half-typed at its prompt. Queued
messages run after the current or next turn ends. Do not build your
own `emacsclient --eval` to insert and submit text: that sends
whatever Tim is typing along with your message.

## Finding and starting sessions

- `timvisher_emacs session get-server <session>` prints the Emacs
  pid and server socket hosting a session, as JSON.
- `timvisher_emacs server ls` lists every live Emacs server by pid.
- Start a new agent-shell with a first prompt in a given Emacs:

  ```bash
  timvisher_emacs session start --emacs <pid> --agent claude \
    --prompt-file /tmp/x.prompt
  ```

  It prints the new session's id, and for Claude its name and ref
  (Codex gets only the id; keep it). For a worktree's Emacs, get the
  pid with `ntmux3 get-editor-pid <session or path>`. To start one in a
  brand-new worktree, use the `worktree` skill's
  `TIMVISHER_NTMUX3_AI_AGENT` variables.

  Do not call agent-shell's start commands through emacsclient
  instead: they paste the current line of whatever buffer Tim has open
  into the new prompt.

## Wedged sessions

```bash
timvisher_emacs session is-wedged <session>        # jq -e .wedged
timvisher_emacs session recover fork <session>     # [--message-file F]
```

`is-wedged` calls a busy session wedged when its agent process is
dead, no prompt request is in flight, or it has been silent for 300s
with no tool call running; `.reasons` says which. Silence during a
running tool call is a long tool call, not a wedge.

`recover fork` forks the session into a new shell, shows the new shell
in the old one's windows, kills the old one, and tells the new one it
is a recovery fork, carrying the old shell's queued prompts in that
one note. It kills a shell, so recover only a session that is yours
or that Tim asked you to recover.

## Errors

Failures are aictl instructions on stderr (`code`, `message`,
`suggestions`); `timvisher_emacs --help` documents every subcommand.
