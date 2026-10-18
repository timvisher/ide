# 1Password CLI (`op`)

## Vault and item operations

- Create SSH key: `op item create --category 'SSH Key' --title '<title>'
  --vault '<vault>' --ssh-generate-key=<type>`
- Get field value: `op item get '<title>' --vault '<vault>' --fields
  '<field-name>'`
- List items: `op item list --vault '<vault>'`
- SSH key generation supports: `ed25519`, `rsa`, `rsa2048`, `rsa3072`,
  `rsa4096`
- When passing item titles or field names with spaces, use quotes
- Vault names are case-sensitive

## Authorization prompts

These were learned the hard way, more than once. Read them before
debugging any `op` or signing failure.

### How authorization works

- `op` authorizes through the 1Password desktop app. When it needs
  approval, the app shows a dialog: **"1Password Access Requested —
  Allow <app> to get CLI access — <account> — Authorize with Touch
  ID"**. `<app>` is the app 1Password holds responsible, not the
  command. Under tmux it says `tmux`.
- An approval belongs to a terminal session and lasts about 30 minutes
  (Tim's observation; 1Password's docs say 10 minutes idle, 12 hours
  at most). Everything run from that session rides on it.
- Do not use `tty` to check for a terminal: it only tests stdin, which
  is a pipe in agent tool calls. Use `ps -o tty= -p $$`, and walk the
  parents if it matters.

### There is no reliable way to check without prompting

- `op whoami` (with or without `--account`) is wrong in both
  directions. It has returned 0 while the very next command opened a
  dialog (2026-10-18), and printed `account is not signed in` while
  `op read` and `op inject` worked (2026-10-02, 10-05, 10-16). Never
  gate on it.
- `op signin`, or any real command, opens the dialog when one is
  needed. Wrapping it in `timeout` does not take the dialog down: it
  stays on screen after the process is killed, waiting for Tim to
  dismiss it. A `timeout` probe therefore costs Tim a dialog every
  time it hits.
- The exit status under `timeout` is not trustworthy either (124 one
  time, 0 another, while the dialog was still pending). Judge by
  elapsed time: a command still running after a few seconds is
  waiting on a prompt.
- A screenshot (the `screen-capture` skill) shows a pending dialog
  plainly, centered on the main display. Use it to confirm what a hung
  command is waiting for.

### What to do instead

1. Check whether Tim is away with the `away-status` skill before
   starting anything that may prompt.
   - Away: do not start it. Use that skill's fallbacks.
   - Present: say a prompt is coming, then run it.
2. Batch `op` work into one Bash call, signing in first, so Tim
   answers one prompt instead of one per command:
   ```bash
   op signin --account <account> >/dev/null &&
     a=$(op read 'op://<vault>/<item>/<field>') &&
     b=$(op read 'op://<vault>/<item>/<field>')
   ```
3. Never start several `op` processes in parallel before the session is
   authorized: each one prompts separately. Serialize the first call.
4. When retrying after a prompt, run the command in the background with
   a generous timeout so Tim has time to approve.
5. An unanswered prompt ends in `authorization timeout` after about 60
   seconds (seen from `eval "$(op signin)"`).
6. If every new shell prompts, look for stale `op://` references
   inherited from the environment, for example
   `tmux show-environment -g | grep 'op://'`.

## Commit signing through the 1Password SSH agent

- Git signs with an SSH key held in 1Password (`gpg.format ssh`,
  `commit.gpgsign true`). `SSH_AUTH_SOCK` may point at a launchd socket
  that is a symlink to 1Password's `agent.sock`; `ls -la
  "$SSH_AUTH_SOCK"` shows which.
- `ssh-add -l` lists the agent's keys without prompting. Producing a
  signature can prompt.
- `agent: client error: EOF` or `fatal: failed to write commit object`
  from `git commit` or `git rebase` **always** means a 1Password prompt
  went unanswered. Do not diagnose further (signing-tool "doctor"
  output and key checks are red herrings). If Tim is present, ask for
  approval and retry the same command; if Tim is away, follow the
  `away-status` fallback.
- Fallback while Tim is away: commit with `--no-gpg-sign`, then re-sign
  before anything is pushed:
  ```bash
  git log --format='%h %G? %s' @{u}..HEAD    # N = unsigned
  git rebase --keep-base --force-rebase --gpg-sign @{u}
  ```
  Unsigned commits must never be pushed where signing is required.
- Tim reports signing shares the CLI's approval timer.
