---
name: github
description: GitHub interactions via `gh` CLI, including drafting `pr.md` / `issue.md` for the `timvisher_gh` workflow, PR creation and editing, CI/checks/status, releases, and repo metadata. Use when a user references github.com, PR numbers/links, or needs to prepare a PR or issue description.
---

# GitHub

## Overview
Draft a `pr.md` or `issue.md` at repo root that `timvisher_gh` can consume. The file must have a single-line title, a blank line, then the body starting on line 3. For multi-commit branches, the PR title and summary must represent the whole branch, not just the latest commit.

## File format
Both `pr.md` and `issue.md` use the same layout:

```
<Title line>
                          ← blank line 2
<Body starting on line 3>
```

`timvisher_gh` uses `head -n1` for the title and `tail -n+3` for the body. A missing blank line will drop content.

## Workflow — creating a PR

### 1) Gather context
Run commands from anywhere by anchoring to the repo root:

```bash
cd "$(git rev-parse --show-toplevel)"
```

Collect the branch range and changes you need to summarize:

```bash
base_branch=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
commit_count=$(git rev-list --count "${base_branch}..HEAD")

git log --oneline "${base_branch}..HEAD"
git status --porcelain
```

If the repo uses `upstream`, adjust the `origin` reference accordingly. Use `rg` or `git grep` for targeted scans; do not use `find -exec`.

### 2) Decide the title
Rules:
- The title is plain text — **never** prefix it with `# ` or any markdown heading syntax. `timvisher_gh` reads line 1 verbatim as the PR/issue title.
- If `commit_count <= 1`, use the single commit subject as the title.
- Otherwise, write a new title that summarizes the whole branch (imperative, 50-72 chars, avoid trailing punctuation).

If `pr.md` already exists (for example from `timvisher-EXP-pull-request-file`), replace the first line with the branch summary unless there is only one commit.

### 3) Build the body
Start line 3 with the PR body. Keep a blank line on line 2.

Never put `## Summary` or any heading before the opening paragraph — the opening paragraph *is* the summary. A heading there is just visual noise.

Recommended structure (adapt to any repo template):

```
<Title line>

- What changed and why (branch-level)
- Key behavior or risk changes
```

If `.github/PULL_REQUEST_TEMPLATE.md` exists, append its contents after your summary and fill all placeholders. Do not leave TODOs or empty checklists.

### 4) Quick checks
- Ensure `pr.md` lives at repo root.
- Ensure line 2 is blank (the PR body starts on line 3).
- Ensure the title and summary reflect all commits when `1 < commit_count`.

### 5) Create the PR
```bash
timvisher_gh pr
```

This pushes the branch and creates the PR, storing the URL in `pr.md.url`.

## Workflow — creating an issue

Draft `issue.md` using the same format (title on line 1, blank line 2, body from line 3), then run:

```bash
timvisher_gh issue
```

The URL is stored in `issue.md.url`.

## Workflow — marking a PR ready for review

Wait for CI checks to pass, then remove draft status:

```bash
timvisher_gh pr ready
```

- Polls `gh pr checks` until all non-excluded checks pass, then runs `gh pr ready`
- Fails immediately if any check has `bucket == "fail"`
- Per-repo exclude patterns at `~/.config/timvisher/ide/bash/bin/timvisher_gh.config/repos/OWNER/REPO/pr/ready/exclude-checks.txt` ignore meta-checks (like mergegate) that never complete until all other checks pass
- One regex pattern per line; `#` comments and blank lines are skipped
- Override the default 10-second poll interval with `TIMVISHER_GH_PR_READY_POLL_INTERVAL`

## Workflow — editing an existing PR or issue

After modifying `pr.md` or `issue.md`, push the updates to GitHub:

```bash
timvisher_gh pr edit     # reads URL from pr.md.url
timvisher_gh issue edit  # reads URL from issue.md.url
```

## Workflow — posting a PR comment

Write the comment body to a file (e.g. `comment.md`), then post it:

```bash
timvisher_gh comment comment.md                                    # PR URL from pr.md.url or Chrome
timvisher_gh comment --pull-request=https://github.com/o/r/pull/1 comment.md  # explicit PR URL
```

The comment URL is stored in `comment.md.url`. Running `timvisher_gh comment comment.md` again when `.url` exists opens it in the browser.

## Workflow — editing an existing comment

After modifying the comment file, push the update:

```bash
timvisher_gh comment edit comment.md   # reads URL from comment.md.url
```

## Workflow — replying to a review comment

To reply to an inline review comment (discussion thread), write the reply body to a file and pass the comment URL:

```bash
timvisher_gh comment reply 'https://github.com/o/r/pull/1#discussion_r123456' reply.md
```

The `<comment-url>` must contain `#discussion_r<ID>` — this is the URL of the specific review comment you are replying to. The reply URL is stored in `reply.md.url`. Running the same command again when `.url` exists opens it in the browser instead of posting a duplicate.

## General GitHub interactions

When interacting with GitHub (github.com), always use the `gh` CLI. This includes viewing PRs, checking CI status, browsing releases, and querying repo metadata.

## Account selection

`gh` on `PATH` is a shim that picks the gh account for each call, so the same command works across orgs that only one of several accounts (e.g. a personal account and an enterprise-managed one) can see. Don't set `GH_TOKEN` or switch accounts yourself; name the target and let the shim choose.

It finds the target org in this order:

1. For `gh api`: `-R OWNER` or `-R OWNER/REPO`, then the endpoint (`repos/OWNER/...`, `orgs/OWNER`, `users/OWNER`).
2. Otherwise: a github.com URL given as the target of a `gh pr`, `gh issue` or `gh repo` command, or the repository argument of `gh repo` (`gh pr view <url>`, `gh repo view OWNER/REPO`); then `--repo`/`-R`; then `--owner` for `gh search` and `gh project`.
3. `GH_REPO`, then the cwd's git remotes on github.com, the way gh picks its base repo (the `gh repo set-default` choice, then `upstream`, `github`, `origin`, then any other remote).

It then uses the account configured for that org in `timvisher_gh.config/orgs/<owner>/account`. An owner with no mapping that is itself one of the configured accounts (a user's own namespace) uses that account. Otherwise gh's active account is used.

- **`gh api` needs `-R`** unless its endpoint names the owner or uses `{owner}`/`{repo}` placeholders: `gh api -R OWNER user`. GraphQL, `user`, `search/...` and similar endpoints fail with `gh_api_owner_required` without it. The shim removes `-R` before running gh, and `-R OWNER/REPO` also sets `GH_REPO` for placeholders. The agent guard blocks `-f`/`-F`, so agents can't run GraphQL queries this way.
- **Calls that select an account print one aictl instruction** saying which account and why: `gh_account_selected` or `gh_account_active` (no target org, or no account for it). `gh auth`, `config`, `alias`, `completion`, `version` and help requests are left alone and print nothing.
- **A mapped account without a token stops the call** with `gh_account_token_unavailable` instead of running as a different account.
- **A `GH_TOKEN` or `GITHUB_TOKEN` already in the environment wins.** The shim uses it as-is and says so with `gh_account_deferred`; a caller-set `GH_REPO` also satisfies `gh api` without `-R`.
- **`--help` works for every command** and runs `gh help <command>` without running anything. `-h` does too, except where it takes a value (`gh auth ... -h HOST`, `gh repo create -h URL`). An extension's help shows gh's generic entry for it, not the extension's own usage.

## Notes
- **No hard line breaks in paragraphs.** Write each paragraph as a single long line. Let the renderer or editor handle wrapping. Only use line breaks for list items, headings, code blocks, and between paragraphs (blank lines).
- Prefer `<=`/`<` comparisons in any pseudocode or scripts.
- `pr.md` and `issue.md` are always ignored; never offer to add or commit them.
