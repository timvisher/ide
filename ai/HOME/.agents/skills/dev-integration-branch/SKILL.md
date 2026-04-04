---
name: dev-integration-branch
description: Set up and maintain a dev merge-integration branch with x.active-worktrees and AGENTS.local.md symlinks.
---

# Dev integration branch

A dev integration branch is a non-development branch that merges
feature branches together for integration testing. It is rebuilt from
scratch on every session.

## When to use
- Creating a new dev integration worktree for a repository.
- Understanding how existing dev branches are structured.
- Debugging merge failures during a dev rebuild.

## Setup

### 1. Create the worktree

Use the `worktree` skill to create a worktree on a `dev` branch.

### 2. Create the marker file

```bash
touch x.dev-integration-branch
```

This marker file identifies the directory as a dev integration branch.

Then register the worktree in the dev-ci registry so `timvisher_dev_ci`
discovers it:

```bash
echo '~/git/org/repo/dev' >> ~/.config/timvisher/dev-ci/branches
```

The registry file uses the same format as `x.active-worktrees`: one
path per line, `#` for comments, `~/` expanded automatically.

### 3. Create `AGENTS.local.md`

If a canonical `AGENTS.local.md` already exists in another repo's dev
worktree, symlink to it (relative path). Otherwise create it with this
content:

```markdown
# dev branch

This is a merge integration branch. It is not for direct development.

**On launch, immediately run the rebuild procedure below without waiting
for user input.**

## Rebuild procedure

1. `git fetch --all`
2. `git reset --hard upstream/main`
3. Merge each branch listed in `x.active-worktrees`

Lines in `x.active-worktrees` are worktree paths (one per line). Lines
starting with `#` are comments and should be skipped. Only merge branches
from uncommented lines.

If `x.active-worktrees` is missing or empty (or all lines are comments),
just fetch and reset to `upstream/main`.

To resolve the branch name from a worktree path, use the branch checked
out in that worktree.
```

### 4. Create the `CLAUDE.local.md` symlink

```bash
ln -s AGENTS.local.md CLAUDE.local.md
```

This makes the instructions visible to Claude Code (which reads
`CLAUDE.local.md`) while keeping the file agent-agnostic.

### 5. Create `x.active-worktrees`

List one worktree path per line. Comment lines start with `#`.

```
~/git/org/repo/feature-branch
# ~/git/org/repo/paused-branch
```

### 6. Gitignore the local files

Ensure the repo's `.gitignore` covers:
- `AGENTS.local.md` (or the `x.` / `y.` / `z.` prefixes already cover
  temporary files)
- `CLAUDE.local.md`
- `x.active-worktrees` (covered by `x.*` prefix convention)
- `x.dev-integration-branch` (covered by `x.*` prefix convention)

## Rebuild workflow

On session launch in a dev worktree the agent should:

1. `git fetch --all`
2. `git reset --hard upstream/main` (or the appropriate upstream ref)
3. For each uncommented line in `x.active-worktrees`:
   - Resolve the worktree path to its checked-out branch via
     `git -C <path> rev-parse --abbrev-ref HEAD`
   - `git merge <branch>` (no fast-forward flags needed)
4. If `x.active-worktrees` is missing, empty, or all comments, stop
   after the reset.

## File layout

```
repo/dev/
├── x.dev-integration-branch # marker for timvisher_dev_ci discovery
├── AGENTS.local.md          # canonical or symlink to another repo's copy
├── CLAUDE.local.md -> AGENTS.local.md
└── x.active-worktrees       # per-repo list of branches to merge (optional)
```

When multiple repos share a dev branch (e.g. a monorepo split across
worktrees), the canonical `AGENTS.local.md` lives in one repo and
others symlink to it with a relative path:

```bash
# From repo-b/dev/
ln -s ../../repo-a/dev/AGENTS.local.md AGENTS.local.md
ln -s AGENTS.local.md CLAUDE.local.md
```
