---
name: away-status
description: Check whether Tim is away from the Mac (screensaver, screen lock, or 10+ minutes without input) before anything that needs Tim to answer a prompt. Use when an operation that normally works silently starts failing, hanging or prompting because a cached approval lapsed — 1Password (git commits, op, credential resolution; approvals last ~30 minutes), browser SSO/OIDC and device-code sign-in (~24 hours), Touch ID/sudo, or macOS permission dialogs — and before stopping to ask Tim something or sending a notification.
---

# Away status

## When to use

Check before doing anything that only works if Tim answers a prompt.
Many operations work silently for a while after Tim approves them once,
then start prompting again when that approval expires:

- **1Password**: git commits (signing), `op`, and anything that
  resolves credentials through 1Password. Approvals last up to ~30
  minutes.
- **Browser auth**: SSO/OIDC and device-code flows such as
  `gh auth` and AWS SSO. Approvals last up to ~24 hours.
- **Other prompts**: Touch ID or `sudo`, macOS permission dialogs,
  `y` scripts Tim has to run, and questions you want to stop and ask.

A system-extensions repo may add an `away-status.<company>` skill
naming the work-specific tools and repos; load it too when it exists.

The moment to check is when one of these **starts failing, hangs, or
opens a prompt** after working earlier in the session. That is the
sign the approval expired. Also check before deliberately starting
one, and before relying on a desktop notification being seen.

## Workflow

1. Read the status, which a LaunchAgent refreshes every 60 seconds:
   ```bash
   cat ~/.local/state/timvisher/away-status/status.json
   ```
   ```json
   {"checked_at":"2026-10-18T07:52:14-0400","checked_at_epoch":1792324334,
    "idle_seconds":0,"idle_threshold_seconds":600,"screensaver_active":false,
    "screen_locked":false,"idle":false,"away":false,"away_reasons":[]}
   ```
   If the file is missing or `checked_at_epoch` is more than 180
   seconds old, run `timvisher_away_status` instead. It prints the
   same object, checked live.

2. If `away` is true (`away_reasons` says which of `screensaver`,
   `locked` or `idle`), do not retry the prompting operation: every
   retry can queue another prompt waiting for Tim to come back to.
   Do not halt either. Keep making progress that can be checked or
   finished properly later, using the fallbacks below, and record each
   one in the bead so it gets backfilled. Only wait (poll the file with
   a Monitor until-loop for `away` to turn false) when nothing else
   can move.

3. If `away` is false, Tim is at the keyboard. Retry once and say a
   prompt is coming, so Tim knows to look for it.

4. If a command that may prompt is still running after a few seconds,
   take a screenshot with the `screen-capture` skill. A "1Password
   Access Requested" dialog means it is waiting on Tim. If Tim has gone
   away, kill it, say the dialog is still on screen, and fall back.

Do not try to predict a 1Password prompt: `op whoami` is unreliable and
`op signin` under `timeout` leaves its dialog up. The `1password`
skill's reference has the details.

## Fallbacks while Tim is away

- **Commit signing** (1Password SSH key; `git config commit.gpgsign`
  is true in the repo): commit with `--no-gpg-sign` rather
  than stopping. Check away status *before* committing in a signing
  repo, because a commit whose prompt nobody answers hangs until the
  prompt times out. A failed signature reads `agent: client error:
  EOF` / `fatal: failed to write commit object`. List unsigned commits and re-sign them before anything is
  pushed, once Tim is back:
  ```bash
  git log --format='%h %G? %s' @{u}..HEAD    # N = unsigned
  git rebase --keep-base --force-rebase --gpg-sign @{u}
  ```
  Re-signing rewrites the commits, so only do it before they are
  published. Say in the handoff which commits are unsigned.
- **Credentials and browser sign-in** (`op`, SSO): the call
  itself cannot happen without Tim. Do the work around it (code,
  offline tests, a script ready to run) and list the exact commands
  still waiting on auth in the bead and the handoff.
- **Commands Tim has to run**: write the `y` script anyway and
  carry on.
- **Questions**: when the choice can be reversed cheaply, make the
  reasonable call, record it as an assumption in the bead, and flag it
  in the handoff. Wait for anything destructive, outward-facing or
  expensive to undo.

None of this relaxes a guardrail. Never bypass an `aictl_warn`, push,
or publish work that is still unsigned or unvalidated.

## Signals

- `idle_seconds`: IOHIDSystem `HIDIdleTime`, the counter that drives
  the screensaver. Free to read, with no permissions needed. Keyboard,
  mouse and trackpad input resets it; agent activity does not.
- `screensaver_active`: a `ScreenSaverEngine` process exists.
- `screen_locked`: the console session has `CGSSessionScreenIsLocked`.
- `idle`: `600 <= idle_seconds`.

## Setup

The script is `bash/bin/timvisher_away_status` in the IDE repo, run by
`LaunchAgents/com.twonegatives.away-status.plist`. Install or reload it
with `LaunchAgents/bin/start com.twonegatives.away-status`. Its log is
`~/Library/Logs/timvisher_away_status.log`.
