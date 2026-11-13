---
name: agent-shell-sessions
description: Message, find, start, and recover other agent-shell sessions (Claude Code or Codex running in Emacs) with timvisher_emacs. Use whenever you need to put a message into another agent session's prompt (named by its ListAgents name or ref, or its session id), find which Emacs hosts a session, start a new agent-shell with a first prompt, check whether a session is wedged, recover a wedged one, or (only when Tim has said to) answer a session's pending permission prompt or cancel its turn. Never hand-build emacsclient --eval forms for any of this.
---

# Agent-shell sessions

## When to use
- Handing a message, request or handoff to another agent session.
- Spawning a new agent in a worktree's Emacs with a first prompt.
- A session looks stuck: busy for a long time with nothing happening.
- Tim has told you to answer a session's permission prompt or cancel
  its turn.

## Naming a session

Every `<session>` below takes any of the forms `ListAgents` shows:
a name (`ide-3f`), a ref (`4b1e9a`), both as printed
(`"ide-3f [4b1e9a]"`), or a full session id. Names and refs come
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
   timvisher_emacs agent-shell send <session> /tmp/x.message
   ```

It prints `submitted` when the shell was idle, or `queued` when it
was busy or Tim had something half-typed at its prompt. Queued
messages run after the current or next turn ends. Do not build your
own `emacsclient --eval` to insert and submit text: that sends
whatever Tim is typing along with your message.

## Finding and starting sessions

- `timvisher_emacs agent-shell ls` lists every agent-shell in every live
  Emacs with its name, ref, status, queued prompts, buffer and
  directory, and a `blocked` session's pending permission prompt
  title: JSON when you run it (no terminal), a table for Tim.
- `timvisher_emacs agent-shell get-server <session>` prints the Emacs
  pid and server socket hosting a session, as JSON.
- `timvisher_emacs server ls` lists every live Emacs server by pid.
- Start a new agent-shell with a first prompt in a given Emacs:

  ```bash
  timvisher_emacs agent-shell start --emacs <pid> --agent claude \
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
timvisher_emacs agent-shell is-wedged <session>        # jq -e .wedged
timvisher_emacs agent-shell recover fork <session>     # [--message-file F]
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

## Permission prompts and turns

A `blocked` session is waiting on a permission prompt. `agent-shell
send` only queues text behind it, so it cannot answer one.

```bash
timvisher_emacs agent-shell permission-prompt --show <session>
timvisher_emacs agent-shell permission-prompt approve <session>
timvisher_emacs agent-shell permission-prompt approve-always <session>
timvisher_emacs agent-shell permission-prompt deny <session>
timvisher_emacs agent-shell turn cancel <session>
```

These answer and cancel on another session's behalf. Run `approve`,
`approve-always`, `deny` or `turn cancel` only when Tim has explicitly
told you to answer that prompt or cancel that turn, in Tim's own words
or relayed by another agent. Never on your own judgment, however long
the session has waited. Every call is logged with your session as the
caller.

- `--show` prints the latest pending prompt's title and its options
  (`allow_once`, `allow_always`, `reject_once`) as JSON. It exits 1
  with `timvisher_emacs_no_permission_prompt` when none is pending.
  Show it first and check it is the prompt Tim meant.
- `approve`, `approve-always` and `deny` pick that prompt's
  `allow_once`, `allow_always` or `reject_once` option. `deny` also
  interrupts the turn, as the prompt's reject key does. Each prints
  the outcome, and `.next_prompt` if another is now pending.
- `turn cancel` interrupts the running turn the way the shell's
  interrupt key does, waits for the shell to go idle, and leaves an
  idle shell alone.

Do not answer a prompt or cancel a turn through a hand-built
`emacsclient --eval`. Calling a permission button's command from a
server eval has locked an Emacs at full CPU.

## Errors

Failures are aictl instructions on stderr (`code`, `message`,
`suggestions`); `timvisher_emacs --help` documents every subcommand.
