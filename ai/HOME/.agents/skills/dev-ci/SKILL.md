---
name: dev-ci
description: Use timvisher_dev_ci to run a worktree's local CI hooks or inspect the cascade. Triggered ONLY by explicit mentions of `dev ci` / `dev_ci` / `dev-ci` / `timvisher_dev_ci`.
---

# timvisher_dev_ci

Local CI orchestrator for dev integration branches; also exposes
per-worktree hook execution in the controlling TTY.

## When to use

ONLY when the user explicitly says one of:
- `dev ci`
- `dev_ci`
- `dev-ci`
- `timvisher_dev_ci`

Do NOT reach for this on generic "verify tests" / "run tests"
requests. `dev_ci` is unique to this user's setup, not widely
implemented; if the user does not mention it by name, run the
project's tests directly.

For dev branch SETUP (creating new dev integration worktrees, marker
files, registry entries), use the `dev-integration-branch` skill.
This skill is for USING `dev_ci` once it exists.

## Commands

From inside a worktree under `~/git/<org>/<repo>/<branch-parts>/`:

```bash
timvisher_dev_ci run-tests          # run cascade-resolved run-tests.sh
                                    # (foreground, no tmux, no nested agent)

timvisher_dev_ci hooks ls           # show what hooks resolve here

timvisher_dev_ci hooks run          # run all KNOWN_HOOKS that resolve
timvisher_dev_ci hooks run HOOK ... # run named hook(s); hard error on unresolvable

timvisher_dev_ci --help             # full reference
```

When the user mentions `dev_ci` in a "did my changes pass tests?"
context, prefer `run-tests` over `make test` / `golangci-lint` /
`pytest` directly: the hook encodes project-specific build tags,
lint flags, and env vars the raw commands miss.

## Foreground vs orchestrated

- `hooks` / `run-tests` — foregrounded in the controlling TTY. Just
  runs the hook scripts. No pull, no merge, no push, no nested
  agent. Use these when the user wants to check their own work.
- Bare `timvisher_dev_ci` — full orchestrated pipeline (sync +
  integrate + push) via tmux + nested claudeshot agents. A
  different operation. Don't invoke unless the user explicitly
  asks for the full pipeline.

## Errors

All errors emit structured JSON via `aictl_die`. Read the `code`,
`reason`, and `suggestions` fields — the suggestions point at the
next concrete step.

## References

- `timvisher_dev_ci --help` — full reference (synopsis, path
  defaults, hook cascade rules, env vars). Read this rather than
  guessing.
- `dev-integration-branch` skill — for setting up new dev branches.
