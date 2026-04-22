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
