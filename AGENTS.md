# Agent Instructions for IDE Configuration

## Running the Test Suites

The suites in this repo and in system-extensions run only through
`timvisher_tests`, never directly. Each runs at its repo root (a bash
suite as `bash <suite>`, the Python ones through `unittest` and the
conformance runner), in its own throwaway `HOME` built by
`bash/install.bash` from the worktrees under test, with an allowlisted
environment:

```bash
bash/bin/timvisher_tests                                # every suite of both repos
bash/bin/timvisher_tests --suite bash/tests/git         # only this suite (repeatable)
bash/bin/timvisher_tests --overlay <system-extensions>  # a system-extensions worktree other than the installed one
```

`timvisher_dev_ci run-tests` runs the same thing. From a
system-extensions worktree, run `~/git/ide/bash/bin/timvisher_tests`
(or pass `--core <ide worktree>`).

Suites are not executable, and the runner refuses a suite that is, or
that looks like it assigns `HOME` or an `XDG_*` variable itself (a
line-based check, so it is a guard, not a proof). `HOME` and the XDG
dirs move together: a test that needs a different `HOME` uses
`timvisher_tests_fresh_home` (a fresh copy of the template for the
calling subshell) or `timvisher_tests_with_home <dir> <cmd>` (a command
run with `HOME`, every XDG dir and `TIMVISHER_GIT_HOME` under `<dir>`), from
`bash/tests/lib/timvisher_tests.bash`.

## Testing a Worktree

To test changes from a worktree without affecting the live `~/git/ide/`
installation, use `timvisher_tests --shell`:

```bash
bash/bin/timvisher_tests --shell                                   # interactive shell
bash/bin/timvisher_tests --shell bash -c 'source ~/.bashrc && …'   # non-interactive with functions
```

This builds a throwaway `HOME` with `bash/install.bash` from this
worktree and system-extensions (its worktree on this branch if it has
one, else its trunk; `--overlay <path>` picks another), runs the command there with an allowlisted environment, and
removes the `HOME` when it exits. It is a scratch `HOME`, not a
sandbox: `~/git/ide` and `~/.config/timvisher/ide` in it link to the
real worktrees, so writes through them land there, and `--shell` does
not check the worktrees for changes the way a suite run does. Nothing
in it links to your own dotfiles or credentials, so tools that need
them (keychain, `~/.codex`) do not work inside it.

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
