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

## timvisher_dev_ci and `git reset`

`reset_dev_worktree_to_upstream` in `bash/bin/timvisher_dev_ci` is the
only place that script may run `git reset`. A reset to `@{u}` discards
every local commit, and the helper refuses anything that is not a dev
integration worktree (listed in the registry or marked with
`x.dev-integration-branch`) before it fetches or resets.

- Never add another `git reset`, in any form, to `timvisher_dev_ci`.
  Call the helper.
- Never tell a nested agent to reset. Prompts that need to back out of
  a merge use `git merge --abort`.
- `bash/tests/timvisher_dev_ci` fails if a `git reset` command appears
  outside the helper. Do not weaken that test to make room for one.
