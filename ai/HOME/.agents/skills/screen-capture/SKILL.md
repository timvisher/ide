---
name: screen-capture
description: Capture all macOS displays at full resolution to ~/Pictures/agent screen captures/<timestamp>/ and read them back. Use when the user asks you to look at, see, or read their screen.
---

# Screen capture

## When to use
- The user asks you to look at, see, or read their screen.
- The user wants visual context shared (window contents, error dialogs,
  rendered output) that isn't easily described in text.

## Workflow

1. Run the capture script:
   ```bash
   ~/.agents/skills/screen-capture/scripts/capture.sh
   ```
   The script:
   - Detects connected displays via `system_profiler`.
   - Captures each at full native resolution with `screencapture` (no `-x`,
     so the shutter sound plays — the user wants to hear it). When
     `screencapture` is given multiple output paths it writes display 1
     to the first path, display 2 to the second, and so on; the
     `screen-<N>.png` numbering follows that ordering.
   - Writes PNGs to `~/Pictures/agent screen captures/<TIMESTAMP>/screen-<N>.png`
     where `<TIMESTAMP>` looks like `2026-04-29T11-08-27+0000`.
   - Writes a `.cookie` file with session metadata for later cross-analysis.
   - Emits an `aictl_info` instruction on stderr with `code:
     "screen_capture_complete"`, the prose summary in `message`, and one
     `Read '<path>'` entry per PNG in `suggestions` (plus the cookie path).
   - Prints the output directory on stdout for non-structured callers.

2. Read each PNG path called out in the aictl_info `suggestions` array.
   Read is multimodal, so you'll see the image content directly.

3. Describe what's relevant from the captures. Don't enumerate every window —
   focus on what the user asked about.

## Failure modes

Failures come back as `{"type":"instruction","level":"error",...}` via
`aictl_die`, with a code and suggestions you can act on:

- `capture_mkdir_failed` — couldn't create the timestamped directory.
- `no_displays_detected` — `system_profiler` reported zero displays.
- `screencapture_failed` — `screencapture` exited non-zero. Almost always
  this means Screen Recording permission is missing for the agent host
  (System Settings → Privacy & Security → Screen Recording). PNGs that
  come out fully black with a zero exit code share the same root cause —
  the OS produced black frames rather than refusing.
- `screencapture_likely_blocked` — `screencapture` exited zero but at
  least one output PNG is missing or under 1KB. False-positives are
  possible for legitimately near-empty content (sleeping displays,
  locked screens, DRM-protected fullscreen video that the OS captures
  as a near-uniform frame). If the user is intentionally capturing one
  of those, retry once they've dismissed the lock screen / paused the
  protected content.

Diagnostic per-step output (e.g. "detected 3 display(s)") goes through
`logging.bash` (`info`/`warn`/`error`), which auto-emits structured
`{"type":"log",...}` JSON under agent context but is suppressed below
ERROR by default. Export `timvisher_logging_log_level=INFO` to see it.

## Cookie file

Each capture directory contains a `.cookie` file with:
- ISO 8601 timestamp and the directory's timestamp slug
- `user`, `host`, `cwd`, `$$`, `$PPID`
- Parent process command (helps identify which Claude Code / Codex / etc.
  session triggered the capture)
- `CLAUDE_*` env vars, with a denylist of secret-bearing suffixes
  applied; the script is the source of truth for what's filtered
- `TERM_SESSION_ID`, `ITERM_SESSION_ID` if set
- Per-display resolution info
- File listing

The cookie lives under `~/Pictures/agent screen captures/<TIMESTAMP>/`
and persists indefinitely; pruning is manual. Two leak vectors to be
aware of:

- The `CLAUDE_*` prefix alone does not guarantee non-secret values
  (e.g. a `CLAUDE_API_KEY` would match). The denylist in the script is
  the actual safety mechanism — extend it there if a new secret-bearing
  name appears.
- The recorded parent command line includes any argv values, so a
  parent invoked with secrets on its command line (a token passed as
  a positional arg, etc.) leaks them into durable storage. The cookie
  is most useful for ordinary interactive sessions where parent argv
  is benign.
