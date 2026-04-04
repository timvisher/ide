---
name: pr-review
description: Review a GitHub pull request by checking CI status, analyzing failures, and delegating to git-branch-review for code review once CI passes. Use when asked to review a PR, check PR CI, fix CI failures, or when given a GitHub PR URL.
---

# PR review

## When to use
- Reviewing a pull request end-to-end (CI + code).
- Checking CI status on a PR and analyzing failures.
- Fixing CI failures on a PR.
- Given a GitHub PR URL or PR number.

## Workflow

### 1) Identify the PR

Resolve the PR in this order:

1. **Explicit URL or PR number** — if the user provided one, use it directly.
2. **`pr.md.url` file** — check for `$(git rev-parse --show-toplevel)/pr.md.url`. If it exists, read the PR URL from it (created by `timvisher_gh pr`; see the `github` skill).
3. **Current branch** — try `gh pr checks --json link,state,name` which auto-detects the PR for the current branch.
4. **Commit SHA fallback** — if no PR is found:
   ```bash
   commit_sha=$(git rev-parse HEAD)
   repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   pr_number=$(gh api "repos/${repo}/commits/${commit_sha}/pulls" --jq '.[0].number')
   gh pr checks "$pr_number" --json link,state,name
   ```

### 2) Assess CI status

Categorize all checks by state (FAILURE, SUCCESS, IN_PROGRESS, PENDING). Group failures by priority:

1. **Build failures** — block everything else
2. **Test failures** — indicate broken functionality
3. **Lint/formatting failures** — usually quick to fix
4. **Other checks** — security scans, deploy previews, etc.

### 3) If CI is failing — analyze and fix

For each failed check, fetch logs based on the CI system:

**GitHub Actions** (links point to `github.com`):
```bash
gh run view <run_id> --log-failed
```

**Other CI systems**: Check for platform-specific skills (e.g., `pr-review.datadog` for DDCI/GitLab CI at Datadog).

For each failure:
- Identify the root cause (specific test, file, error message).
- Determine if the failure is caused by this PR's changes or is unrelated (flaky test, infrastructure issue).
- Propose concrete fixes with file paths and line numbers.

Present a summary:
```
CI Failure Analysis
===================
Found N failed job(s):

1. [Job Name] - [CI System]
   Root Cause: [Brief description]
   Fix: [One-line summary]
   PR-related: yes/no
```

Apply fixes after user confirmation.

### 4) If CI is passing — code review

Once all CI checks pass, delegate to the `git-branch-review` skill for a full code diff review. Do not duplicate that skill's work here.

### 5) Retry flaky failures

If failures appear unrelated to the PR (flaky tests, infra issues), offer to retry. For GitHub Actions:

```bash
gh run rerun <run_id> --failed
```

For other CI systems, check platform-specific skills for retry capabilities.

## Notes
- Always use `gh` CLI for GitHub interactions.
- Platform-specific CI systems (GitLab, DDCI, etc.) are handled by extension skills — this skill covers the generic GitHub-based workflow.
- Related skills: git-branch-review, github (PR creation via `timvisher_gh`, `pr.md.url` management).
