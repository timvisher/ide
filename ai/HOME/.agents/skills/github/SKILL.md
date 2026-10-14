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

`gh` on `PATH` is a shim that picks the gh account for each call, so the same command works across orgs that only one of several accounts (e.g. a personal account and an enterprise-managed one) can see. It picks an account only when the target is obvious, and otherwise stops and asks you to name it. Don't set `GH_TOKEN` or switch accounts yourself.

**Name the target with `-R` before the subcommand:** `gh -R OWNER/REPO pr view 5`, `gh -R OWNER gist list`, `gh -R OWNER api user`. `-R VALUE`, `-RVALUE`, `-R=VALUE`, `--repo VALUE` and `--repo=VALUE` all work, in any order with `--help`/`--version`. The shim removes it and sets `GH_REPO` from an `OWNER/REPO` value, so it works for every command, including ones gh gives no `-R` (`api`, `gist`, `search`, ...).

The obvious targets, in order:

1. `-R`/`--repo` before the subcommand.
2. For `gh api`, an endpoint right after `api` that starts with `repos/OWNER/`, `orgs/OWNER` or `users/OWNER`.
3. `GH_REPO` (`[HOST/]OWNER/REPO`).
4. The cwd's git remotes, when they're all on github.com and all name the same owner.

It then uses the account configured for that owner in `timvisher_gh.config/orgs/<owner>/account` (owners match without regard to case; an owner that is itself a configured account uses that account), or gh's active account if there's no mapping. A target on another host (`-R`, `GH_REPO`, `GH_HOST` or `--hostname` naming it) keeps gh's own account for that host.

**It stops with `gh_target_required`** when there's no obvious target, or when something after the subcommand might name a different one:

- `-R`/`--repo` after the subcommand (except `gh search`'s and `gh codespace`'s own `--repo`);
- a github.com URL whose owner isn't the one picked (a URL with no `-R` at all counts), or any URL on another host;
- for `gh api`, a `repos/`, `orgs/` or `users/` path naming a different owner; for `gh repo`, an `OWNER/REPO` argument naming a different owner;
- remotes naming different owners, or a remote the shim can't place on github.com.

These checks match loosely on purpose: a false match (say, a URL inside `--body`) costs a stop, never a wrong account. Fix any stop by putting `-R` before the subcommand.

- **Calls that select an account print one account-selection instruction** (`gh_account_selected` or `gh_account_active`, plus any notices) to stderr, for every operator. `gh auth`, `config`, `alias`, `extension`, `help`, `completion` and `version` pass straight through.
- **A mapped account without a token stops the call** with `gh_account_token_unavailable`.
- **A `GH_TOKEN` or `GITHUB_TOKEN` already in the environment wins**, with a `gh_account_deferred` notice.
- **Help:** `-h`/`--help` as the last argument (or before the subcommand) runs `gh help <command> ...` and nothing else, even if it was really a flag's value.
- **The agent guard blocks `-f`/`-F`**, so agents can't run GraphQL queries through `gh api`.

## Notes
- **No hard line breaks in paragraphs.** Write each paragraph as a single long line. Let the renderer or editor handle wrapping. Only use line breaks for list items, headings, code blocks, and between paragraphs (blank lines).
- Prefer `<=`/`<` comparisons in any pseudocode or scripts.
- `pr.md` and `issue.md` are always ignored; never offer to add or commit them.
