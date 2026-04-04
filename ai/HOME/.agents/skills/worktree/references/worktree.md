# Worktree management

## Directory layout

Worktrees live under `~/git/` following a hierarchical structure:

```
~/git/<org>/<repo>/<branch-part>/<branch-part>/…/
```

Examples:
- `~/git/DataDog/appgate/timvisher/scratch/_trunk_/`
- `~/git/DataDog/dd-source/main/`

Bare repo caches live at:
`~/.cache/timvisher_git_worktrees/repo_trunks/<org>/<repo>/`

## Creating worktrees

### Interactive (attaches to the new tmux session)

```bash
ntmux3 org/repo/branch-name
ntmux3 https://github.com/org/repo/pull/123
```

### Detached (prints session name, does not attach)

```bash
ntmux3 -d org/repo/branch-name
ntmux3 -d https://github.com/org/repo/pull/123
```

Detached mode:
- Prints the tmux session name to **stdout**.
- Prints an INFO hint with the attach command to **stderr**.
- Skips the "inside tmux" guard, so it works from within an
  existing session.
- If the session already exists, prints its name without
  creating a new one.

### Attaching to an existing session

```bash
ntmux3 org/repo/branch-name   # re-attaches if session exists
ntmux session-name             # attach by tmux session name
```

## Lower-level: ntmux

`ntmux` creates tmux sessions with a standard window layout
(editor, admin, services, db, tests). Like `ntmux3`, it is a shell
function (not a binary) — invoke it directly. It also supports `-d`:

```bash
ntmux -d session-name /path/to/dir
```

## Typical agent workflow

To spin up a worktree without blocking the current terminal:

```bash
session_name=$(ntmux3 -d org/repo/branch-name)
```

The agent can then use the worktree directory at
`~/git/org/repo/branch-name/` without needing to attach.
