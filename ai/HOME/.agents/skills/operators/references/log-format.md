# Looper log format, and lessons from the first operator

The examples below are illustrative: they recast what the first
operator saw (a production cutover and its burn-in) as a database
failover from an old primary to a new one.

## Log format
Each run is bracketed by `run begin` and `run end rc=<n>` lines so a
summarizer can find the latest complete run. Between them, one line
per target, each with a context prefix naming the mode and target and
one status:
- `ok`: working.
- `WARN`: degraded but still serving. It leaves rc at 0.
- `FAIL`: not working.
- `CRITICAL`: report immediately.
- `skip`: the check doesn't apply in the current state; say why.

One run of an admin looper (ok lines trimmed), then a skip from a
looper whose check only applies on one client route:

```text
[admin old-primary -] 2026-11-02T16:12:12+0000 run begin
[admin old-primary -] 2026-11-02T16:12:21+0000 ok discovery db.example.internal: registered
[admin old-primary -] 2026-11-02T16:12:21+0000 WARN replicas region-b: 0 of 3 healthy, 3 warning (replication lag over 30s)
[admin old-primary -] 2026-11-02T16:12:22+0000 run end rc=0
[client new-primary direct] 2026-11-02T16:07:04+0000 skip route: client on "old-primary direct", not "new-primary direct"
```

## Pair admin checks with user-path checks
An admin-status check can be wrong about what users see. On the first
operator, the admin looper logged a CRITICAL like `CRITICAL replicas
region-b: 0 of 3 healthy` because it counted members in warning as
down. Thirteen seconds later the user-path looper reached a service
through that same site:

```text
[client old-primary direct] 2026-11-02T16:07:34+0000 ok site region-b: orders.example.internal:5432
```

So give degraded-but-serving its own status (`WARN`), and pair every
admin-status check with a user-path check that can contradict it.

## An agent looper drifting from the format

After the operator warned one agent-shell looper about something it
should also watch, the looper started appending its own line to its
log:

```text
[client new-primary direct] 2026-11-02T16:38:35+0000 run end rc=0
2026-11-02T16:38:35Z ok [dns db.example.internal] new-primary: still resolves to the old primary
```

The information was useful, but the line has no context prefix, uses a
different timestamp form and sits after the run's end marker, so a
summarizer misses or misreads it. The log format then depends on
whichever agent writes it. The fix was to put that check in the
script, as a new mode of the check command.

## An agent looper that silently stopped

The same agent-shell looper stopped looping after its 16:38Z run. The
operator had messaged it new instructions, and that ended its turn
without re-arming its wakeup. It wasn't wedged by `is-wedged`'s
definition: live, idle, nothing queued, so nothing flagged it. Its runs
had been 11 minutes apart; comparing the log's last run with that
cadence caught it 14 minutes late, and it restarted at 16:52Z.

So messaging an agent looper can stop its loop, and liveness has to
come from the logs (last run age against cadence), not from session
state. A script or launchd looper has neither failure mode.
