---
name: codex-review
description: Run a skeptical code review via Codex CLI (`codex exec`). Use when you want an independent second opinion on your own work — uncommitted changes, a branch, or specific files.
user-invocable: true
---

# Codex review

## When to use
- You want an independent review of code you just wrote or modified.
- The user asks you to review yourself or get a second opinion.
- Before committing or creating a PR, to catch issues you might have missed.

## How it works

This skill shells out to `codex exec` — a separate AI agent process —
to review code with fresh eyes. The review runs in a read-only sandbox
so it cannot modify anything.

## Workflow

### 1) Determine what to review

Ask or infer from context. Common targets:

- **Uncommitted changes** (default): everything staged, unstaged, and untracked.
- **Branch diff**: all commits on the current branch vs upstream.
- **Specific files**: a subset of changed files.

### 2) Compute the diff range

Before building the prompt, determine the correct git range:

```bash
# Check if there are unpushed commits
unpushed=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo "0")
```

- If `unpushed > 0`: use `@{u}..HEAD`
- If `unpushed == 0` and you know which commits to review: use an
  explicit range like `<base-sha>..HEAD` or `HEAD~N..HEAD`
- For uncommitted changes: no range needed, use `git diff` / `git diff --cached`

**Always pass the concrete diff command in the prompt** so Codex doesn't
have to figure out the range itself.

### 3) Build the codex command

Use `codex exec` with a review prompt. Always use `--sandbox read-only`
and `--full-auto` so the review runs non-interactively without modifying
anything.

Template:

```bash
codex exec --full-auto --sandbox read-only \
  -o /tmp/codex-review-output.md \
  "With a skeptical eye, do a thorough review of <TARGET>.

Examine:
- Correctness: logic errors, off-by-ones, missed edge cases
- Completeness: stubs, TODOs, missing error handling, untested paths
- Consistency: does the change follow surrounding codebase patterns?
- Safety: security issues, resource leaks, injection risks
- Clarity: naming, comments, would a future reader understand?

IMPORTANT: Your ONLY task is code review. Do NOT run any project tooling,
task trackers, issue trackers, or workflow tools (bd, beads, todo, etc.).
Do NOT try to set up the project or install dependencies. ONLY use git
commands (git diff, git log, git show) and file reading to do the review.

Organize findings by severity:
- **Findings**: file:line, severity (high/medium/low), description
- **Missing Tests**: what test coverage gaps exist?
- **Questions/Assumptions**: anything ambiguous or worth calling out

Recent commits on this branch for context:
$(git log --oneline -10)"
```

#### Target examples

**Uncommitted changes:**
```
the uncommitted changes in this repository (staged, unstaged, and untracked files). Run git diff and git diff --cached to see them.
```

**Branch diff:**
```
all changes on this branch compared to upstream. Run git diff @{u}..HEAD to see the full diff. If that is empty, try git diff origin/main..HEAD or git diff HEAD~N..HEAD using the commit count from git rev-list --count @{u}..HEAD.
```

**Explicit commit range** (when commits are already pushed):
```
the last N commits: <commit summaries>. Run git diff <base-sha>..HEAD to see the full diff.
```

**Specific files:**
```
the following files: <file1> <file2>. Read each file and review thoroughly.
```

### 4) Run and capture output

```bash
codex exec --full-auto --sandbox read-only \
  -o "$(git rev-parse --show-toplevel)/x.codex-review-output.md" \
  "<prompt>"
```

The `-o` flag writes the final agent message to a file. Use the
`x.` prefix so it's gitignored.

### 5) Present findings

Read the output file and present the findings to the user. Summarize
the key points and highlight anything you agree or disagree with based
on your own understanding of the code.

## Important notes

- Always use `--sandbox read-only` — the review must not modify files.
- Always use `--full-auto` — the review must run non-interactively.
- The `-o` flag captures the final response; use it to read results back.
- If the review finds issues you agree with, offer to fix them.
- If the review is wrong about something, explain why to the user.
- The `codex exec` command can take 1-3 minutes to run. Use
  `run_in_background` for the Bash call so the user isn't blocked.
