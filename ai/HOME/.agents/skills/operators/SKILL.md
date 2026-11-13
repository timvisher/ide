---
name: operators
description: Start a persistent operator, a temporary agent "team member" that watches a long-running operation (an apply, a cutover, a burn-in, a rollout, a migration) through loopers that each run one deterministic check on a cadence, and reports only changes to the session that owns the operation. Use when an operation outlives a turn and someone needs to know the moment it changes, without Tim watching it.
---

# Operators

## When to use
- An operation runs for minutes to days (a cutover and its burn-in, a
  terraform apply wave, a rollout, a migration, CI on a stack of PRs)
  and someone should notice the moment its state changes.
- Tim asks for an agent to "keep an eye on", "watch" or "check on"
  something and report back.

## Roles
- **Owner:** the session that owns the operation. It receives the
  operator's reports and relays to Tim what matters.
- **Operator:** an agent-shell that owns the watching. The owner
  starts it, or any session does at Tim's request; either way it
  always reports to the owner. It runs the loopers, reads their logs
  and reports changes.
- **Loopers:** each runs one deterministic check on a cadence and
  appends to its own log. A looper can be a plain script or a minimal
  agent-shell that runs one command per cycle and idles in between.
  Prefer scripts: they need no model calls, their log format can't
  drift, and they don't stop when someone messages them. The first
  operator (a production cutover and its burn-in, 2026-11-02) used five
  single-command agent loopers, and two of them failed in ways a
  script can't (references/log-format.md): one began writing its own
  line in its own format, outside the run markers, and one stopped
  looping after the operator messaged it new instructions. When a
  looper should check something new, put the check in the script. The
  cost savings of scripts are expected, not yet measured.

## Workflow
1. **Write down the operation:** what is being watched, what counts as
   CRITICAL, what "done" looks like, and when watching ends.
2. **Get a deterministic check.** Reuse the operation's own script
   (e.g. a skill's `scripts/smoke`) or write one. Its output follows
   the log format below.
3. **Plan loopers:** one per independent check or mode, each with its
   own log under one directory named for the check, e.g.
   `<topic or worktree>/x.smoke-logs/<looper>.log`, and a cadence
   (about 10 minutes is a good default).
4. **Make modes follow real state.** A looper whose check only makes
   sense in some state (a VPN, a client profile, a feature flag)
   checks that state on every run and logs a `skip` with the reason
   instead of failing. It starts working by itself when the state
   changes.
5. **Add a status summarizer** over the logs (e.g. `smoke status`):
   each looper's latest run, what changed since the run before, and
   which loopers are stale (last run older than their cadence allows).
   Take liveness from the logs, not from session state: a looper that
   stopped can look perfectly healthy. The operator, the owner and Tim
   can all use it.
6. **Start the operator** with the brief in references/brief.md,
   through the `worktree` skill's `TIMVISHER_NTMUX3_AI_AGENT` variables
   or `timvisher_emacs agent-shell start` (`agent-shell-sessions`
   skill). Record it on the operation's bead: name, ref, session id.
7. **Hold the operator to the contract** (below) and check its claims
   against the logs.
8. **Tear down** when the end condition is met: stop every looper,
   have the operator send a final report, close it, and note the
   teardown on the bead.

## Running loopers
- **Today:** run a script looper in its own tmux window of the
  operation's session, or under `nohup`. Use an agent-shell looper
  only for a check that needs judgment every cycle, or that has no
  script yet.
- **Planned on Tim's Mac:** a launchd job per looper, leaving only the
  operator as an agent. launchd would give a looper run-now by name
  (`launchctl kickstart`, with the same arguments and environment as
  timed runs), at most one run at a time, run counts and last exit
  codes from `launchctl print`, no model calls per cycle, survival
  across Emacs and agent restarts, and one-command teardown. The
  operator could kick a looper right after a milestone instead of
  waiting out the cadence. It needs tooling the ide repo doesn't have
  yet:
  - temporary per-looper jobs, loaded from the operation's directory
    rather than installed, so a forgotten looper doesn't return after a
    reboot;
  - kick and status verbs;
  - an explicit environment;
  - a per-run timeout;
  - and proof that the check's credential lookups don't prompt when
    launchd starts them.

  Until that exists, use tmux or `nohup`.

## Log format
Each run is bracketed by `run begin` and `run end rc=<n>` lines. Between
them, one line per target: a context prefix naming the mode and target,
a timestamp, then one status: `ok`, `WARN` (degraded but serving; rc
stays 0), `FAIL`, `CRITICAL` or `skip` (with the reason). Real examples
are in references/log-format.md.

## Pair admin checks with user-path checks
An admin-status check can be wrong about what users see. Give
degraded-but-serving its own status (`WARN`), and pair every
admin-status check with a user-path check that can contradict it. The
first operator's false CRITICAL, contradicted 13 seconds later, is in
references/log-format.md.

## Reporting contract
- A baseline first: every looper's current state.
- After that, only changes: a WARN, FAIL or CRITICAL, a check
  flipping, a mode change (e.g. a profile switch), the operation's
  milestone landing. CRITICAL goes to the owner immediately, once a
  user-path check hasn't contradicted it.
- A list of known, non-critical failures not to chase or re-report.
- Missing local preconditions are explicit and actionable: say what is
  missing, where, and how to fix it ("profile X isn't in Tim's client;
  install it with ..."), never just "not installed".
- Reports go to the owner with `timvisher_emacs agent-shell send`.

## Check claims against the logs
An operator's messages are claims; its logs are evidence. Before
relaying "it adapted" or "all green", find the log lines that show it,
e.g. the first run after a profile switch. "Will adapt" is not
evidence.

## References
- references/brief.md: operator brief template and a script looper
  sketch that writes this log format.
- references/log-format.md: real log lines, the false CRITICAL behind
  pairing admin and user-path checks, and two agent-looper failures.
