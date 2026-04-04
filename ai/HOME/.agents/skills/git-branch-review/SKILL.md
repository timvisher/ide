---
name: git-branch-review
description: Review the entire branch diff against @{u}. Requires upstream set and rebased. Reviews the full changeset, not just the current session.
---

# Git branch review

## When to use
- Reviewing a feature branch before creating a PR.
- The user asks to review the branch, the diff, or the changeset.

## CRITICAL: What this skill IS and IS NOT

This is a review of the **entire changeset represented by the branch** —
every commit between `@{u}` and the branch tip, regardless of who wrote them or
when. This is NOT a review of what you did in this session. This is NOT
a review of the latest commit. You are reviewing ALL changes on this
branch as a unified body of work. Pretend you have never seen any of
this code before.

## Preconditions (enforce before reviewing)

Before any review work, verify both of these. If either fails, stop and
tell the user what to fix.

1. **Upstream must be set.** The current branch must have `@{u}` configured.
   ```bash
   git rev-parse --abbrev-ref '@{u}'
   ```
   If this fails, tell the user to set an upstream:
   `git branch --set-upstream-to=<remote>/<branch>`

2. **Branch must be rebased on top of upstream.** There must be zero
   commits in `@{u}` that are not in `HEAD` (i.e., upstream is an
   ancestor of HEAD).
   ```bash
   git rev-list --count '@{u}..HEAD'   # commits to review
   git rev-list --count 'HEAD..@{u}'   # must be 0
   ```
   If the second count is non-zero, tell the user to rebase first.

## Workflow

### 1) Gather context

```bash
git rev-parse --abbrev-ref HEAD
git rev-parse --abbrev-ref '@{u}'
git rev-list --count '@{u}..HEAD'
git log --oneline '@{u}...'
git diff --stat '@{u}...'
```

### 2) Review the diff

Read the full diff:

```bash
git diff '@{u}...'
```

If the diff is very large, review file-by-file using the `--stat`
output as a guide. Read each changed file's diff individually:

```bash
git diff '@{u}...' -- <path>
```

### 3) Analyze

For each file or logical group of changes, assess:

- **Correctness**: Does the code do what it claims? Are there logic
  errors, off-by-ones, or missed edge cases?
- **Completeness**: Are there TODOs, stubs, or half-finished changes?
  Are all new code paths tested?
- **Consistency**: Does the change follow the patterns and conventions
  of the surrounding codebase?
- **Safety**: Are there security issues, error handling gaps, or
  resource leaks?
- **Clarity**: Is the code understandable? Are names descriptive?
  Would a future reader understand the intent?

### 4) Report

Present findings organized by severity:

- **Must fix**: Bugs, correctness issues, security problems.
- **Should fix**: Inconsistencies, missing error handling, unclear code.
- **Consider**: Style suggestions, minor improvements, alternative
  approaches.

Include file paths and line references for every finding. Quote the
relevant code.

## References
- See references/git-branch-review.md for additional review guidance.
