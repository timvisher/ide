# Agent Instructions for IDE Configuration

## Testing a Worktree

To test changes from a worktree without affecting the live `~/git/ide/`
installation, use `timvisher_tests --shell`:

```bash
bash/bin/timvisher_tests --shell                                   # interactive shell
bash/bin/timvisher_tests --shell bash -c 'source ~/.bashrc && …'   # non-interactive with functions
```

This builds a throwaway `HOME` with `bash/install.bash` from this
worktree and the system-extensions trunk (`--overlay <path>` picks
another), runs the command there with an allowlisted environment, and
removes the `HOME` when it exits. Nothing in it points into the real
`HOME`, so tools that need your credentials (keychain, `~/.codex`) do
not work inside it.

Because `bash -c` is non-interactive, it does not source `.bashrc`
automatically. To test shell functions, source it explicitly.
