# Agent Instructions for IDE Configuration

## Testing a Worktree

To test changes from a worktree without affecting the live `~/git/ide/`
installation, use `bash/tests/bash`:

```bash
bash/tests/bash                              # interactive shell
bash/tests/bash -c 'source ~/.bashrc && …'   # non-interactive with functions
```

This sets up a fake `HOME` at `x.home/` with `x.home/git/ide` symlinked
back to the repo root, runs `bash/install.bash` into it, then execs
bash with `"$@"`.

Because `bash -c` is non-interactive, it does not source `.bashrc`
automatically. To test shell functions, source it explicitly.

## LaunchAgents

Label a LaunchAgent with the reverse-DNS namespace of the tree it ships
from, and name the plist `<label>.plist` to match:

| Where it comes from | Namespace |
|---|---|
| This repo (personal IDE) | `com.twonegatives.<name>` |
| An employer's system-extensions repo | `<reverse-dns company>.timvisher.ide-system-extensions.<name>` |
| Other work for that employer | `<reverse-dns company>.timvisher.<name>` |

Each system-extensions repo spells out its concrete namespaces in its
own `CLAUDE.md`.

The existing `com.timvisher.*` labels predate this; do not copy them.
Deploy or reload one from this repo with `LaunchAgents/bin/start <label>`.
