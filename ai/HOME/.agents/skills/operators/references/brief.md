# Operator brief and looper sketch

## Brief template

Fill this in and send it as the operator's first prompt. The sender
may be the owner or another session acting at Tim's request; the
operator reports to the owner either way.

```text
From the <sender name> agent (session <sender session id>): you're the
operator for <operation>, bead <bead id>. You watch it and report to
<owner name> (session <owner session id>); you don't change it.

Operation: <what is happening, where, and who drives it>.
Done when: <end condition, e.g. burn-in ends Thu 17:00 ET>.

Loopers (start them; don't do their checks by hand):
- <looper name>: runs <command> every <cadence>, logs to <path>.
  Mode: <always | only while <state>, else log "skip <reason>">.
- ...
Status: <summarizer command, e.g. scripts/smoke status>.

Report to the owner with
`timvisher_emacs agent-shell send <owner session id>`:
1. A baseline first: each looper's current state.
2. Then changes only: a WARN, FAIL or CRITICAL, a check flipping, a
   mode change, <milestone> landing. CRITICAL immediately, but first
   check it against the user-path loopers; an admin check can be wrong.
3. Known non-critical failures, don't chase or re-report:
   - <e.g. a decommissioned replica, db-old-3, that still reports down>
4. When a local precondition is missing, say what, where, and how to
   fix it.
5. Back every claim with log lines (path and timestamp).
6. Watch liveness in the logs: a looper whose last run is older than
   its cadence allows has stopped, even if its session looks fine.
   Report it as a change. Messaging an agent looper can stop its loop,
   so check its next run after you do.

Teardown when done: stop every looper, send a final report, then tell
the owner you're ready to be closed.
```

## Script looper sketch

One looper per check and mode. The check prints one
`<status> <target> <detail>` line per target (`ok`, `WARN`, `FAIL`,
`CRITICAL` or `skip`; `WARN` alone leaves rc at 0) and decides its own
mode. The looper adds the context prefix and timestamp, and brackets
each run with `run begin` and `run end rc=<status>` lines.

```bash
#!/usr/bin/env bash
# x.smoke-looper <context> <log> <cadence-seconds> <check command...>
# e.g. x.smoke-looper 'admin old-primary -' x.smoke-logs/admin-old-primary.log 600 scripts/smoke admin old-primary

context=$1
log=$2
cadence=$3
shift 3

if ! mkdir -p -- "$(dirname -- "$log")"
then
  printf 'cannot create log dir for "%s"\n' "$log" >&2
  exit 1
fi

while true
do
  printf '[%s] %s run begin\n' "$context" "$(date -u +%Y-%m-%dT%H:%M:%S%z)" >> "$log"
  (
    set -o pipefail
    "$@" | while IFS= read -r line
    do
      printf '[%s] %s %s\n' "$context" "$(date -u +%Y-%m-%dT%H:%M:%S%z)" "$line"
    done
  ) >> "$log"
  rc=$?
  printf '[%s] %s run end rc=%d\n' "$context" "$(date -u +%Y-%m-%dT%H:%M:%S%z)" "$rc" >> "$log"
  sleep "$cadence"
done
```

Run each looper in its own tmux window of the operation's session (or
under `nohup`), so stopping it is one `kill` or `kill-window` and Tim
can watch it live. If an agent-shell runs the looper instead, its
whole job is the same cycle: run the one command, append its output in
this format, idle until the next cycle.
