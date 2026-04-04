# Git branch review — detailed guidance

## Reminder

You are reviewing the ENTIRE branch diff (`@{u}...`). Every commit,
every file, every line. Not just what you wrote. Not just the latest
commit. The whole thing.

## Precondition checks

### Upstream must exist

```bash
git rev-parse --abbrev-ref '@{u}'
```

If this errors with "no upstream configured", stop. Tell the user:

> This branch has no upstream set. Run:
> `git branch --set-upstream-to=origin/<branch> <branch>`
> Then invoke this skill again.

### Must be rebased

```bash
behind=$(git rev-list --count 'HEAD..@{u}')
```

If `behind` is non-zero, the branch has diverged from upstream. Stop.
Tell the user:

> This branch is `$behind` commit(s) behind `@{u}`. Rebase first:
> `git pull --rebase`
> Then invoke this skill again.

## Review commands

### Overview

```bash
git log --oneline '@{u}...'           # commit list
git diff --stat '@{u}...'             # file summary
git diff --shortstat '@{u}...'        # quick numbers
```

### Full diff

```bash
git diff '@{u}...'
```

### Per-file diff (for large branches)

```bash
git diff '@{u}...' -- path/to/file
```

### Commit-by-commit (when commit structure matters)

```bash
git log -p '@{u}...'
```

### Searching within the diff

```bash
git diff '@{u}...' -G 'pattern'      # changes matching pattern
```

## What to look for

### Correctness
- Logic errors, off-by-one, wrong comparisons
- Null/nil/undefined handling
- Concurrency issues (races, deadlocks)
- Resource management (open files, connections, locks)

### Completeness
- Unfinished TODOs or FIXMEs introduced in this branch
- Missing error handling for new code paths
- Test coverage for new behavior
- Missing documentation for public API changes

### Consistency
- Naming conventions matching surrounding code
- Error handling patterns matching the codebase
- Import/dependency patterns
- Code organization and file placement

### Safety
- Input validation at system boundaries
- SQL injection, XSS, command injection
- Secrets or credentials in code
- Permissions and access control

### Clarity
- Descriptive variable and function names
- Comments where logic is non-obvious
- Reasonable function length and complexity
- Clear separation of concerns

## Report format

Organize findings by severity, not by file:

### Must fix
Items that are objectively wrong: bugs, security issues, data loss
risks. These block merging.

### Should fix
Items that are likely to cause problems: missing error handling,
confusing code, inconsistencies with codebase patterns.

### Consider
Items that are subjective or minor: style preferences, alternative
approaches, potential future improvements.

For every finding, include:
- The file path and line number(s)
- A quote of the relevant code
- What the issue is
- A suggested fix (if you have one)
