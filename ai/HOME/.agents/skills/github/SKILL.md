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
- Ensure `pr.md` lives at repo root (or at `.timvisher_gh/pr/pr.md`).
- Ensure line 2 is blank (the PR body starts on line 3).
- Ensure the title and summary reflect all commits when `1 < commit_count`.

### 5) Create or update the PR
Agents do not push. Hand the human the one-line invocation instead:

```bash
timvisher_gh pr push                      # same as bare `timvisher_gh pr`
timvisher_gh pr push --force-with-lease   # after a rebase or other rewrite
```

`pr push` converges GitHub to the worktree and is safe to rerun after any failure: it pushes the branch (or reports "already pushed"), creates a draft PR from `pr.md` if none is recorded (adopting an existing open PR for the branch instead of duplicating it), and otherwise updates the title and body from `pr.md`. The URL is recorded in `.timvisher_gh/pr/pr.json`. `--force-with-lease` runs `git push --force-with-lease --force-if-includes`; `--force-with-lease=<sha>` leases against a specific remote SHA. `--open` opens the PR afterwards.

The title/body update is guarded by a lease on what `timvisher_gh` last posted (`.posted` in `pr.json`). If someone edited the description on GitHub since then, `pr push` refuses and prints the diff: fold their edits into `pr.md` (a `pr.md` that matches GitHub becomes the new baseline) or delete `.posted` from `pr.json` to overwrite GitHub. Never write ad hoc `y.*.sh` push scripts; everything they did is a `pr push` rerun.

## State directory

`timvisher_gh` keeps per-worktree state in `.timvisher_gh/` at the worktree root (ignored by the global gitignore):

- `pr/pr.md`, `pr/pr.json` (`url` plus the `posted` title/body), `pr/pr.url` (generated from `pr.json`; `cat` or open it), `pr/merged` (merged cookie)
- `issue/issue.md`, `issue/issue.json`, `issue/issue.url`

A `pr.md` or `issue.md` drafted at the worktree root is moved into `.timvisher_gh/` the next time a `pr`, `issue`, or `comment` subcommand runs. Root `pr.md`, `pr.md.url` and `x.merged` symlinks are left behind for older callers; read the PR URL from `.timvisher_gh/pr/pr.url` in new code.

## Workflow — creating an issue

Draft `issue.md` using the same format (title on line 1, blank line 2, body from line 3), then run:

```bash
timvisher_gh issue
```

The URL is recorded in `.timvisher_gh/issue/issue.json`.

## Workflow — marking a PR ready for review

Wait for CI checks to pass, then remove draft status:

```bash
timvisher_gh pr ready
```

- Reports "already ready" (and runs only the ready post-hooks) when the PR is not a draft
- Polls `gh pr checks` until all non-excluded checks pass, runs the ready pre-hooks (e.g. an ARP gate), then runs `gh pr ready`
- Fails immediately if any check has `bucket == "fail"`
- Org and repo exclude patterns at `timvisher_gh.config/{orgs/OWNER,repos/OWNER/REPO}/pr/ready/exclude-checks.txt` (either config root) ignore meta-checks (like mergegate) that never complete until all other checks pass
- One regex pattern per line; `#` comments and blank lines are skipped
- Override the default 10-second poll interval with `TIMVISHER_GH_PR_READY_POLL_INTERVAL`

## Workflow — editing an existing PR or issue

After modifying `pr.md` or `issue.md`, push the updates to GitHub (both use the description lease described above):

```bash
timvisher_gh pr push     # or `pr edit` for only the title/body step
timvisher_gh issue edit  # reads URL from .timvisher_gh/issue/issue.json
```

## Workflow — reading PR feedback

```bash
timvisher_gh pr pull
```

Mirrors the whole conversation into `.timvisher_gh/pr/comments/`, one directory per item, named `<UTC timestamp>-<slug>` so `ls` order is chronological: issue comments and reviews with a body as `<ts>-<author>[-review]/comment.{md,json}`, review threads as `<ts>-<path>-L<line>-thread/thread.{md,json}` with replies in `<ts>-<author>/comment.{md,json}` inside. The JSON carries the node id, URL, author, and (for threads) path, line, starting review and resolved state. Safe to rerun: remote edits flow down, your unpushed edits to your own comments are kept, and intent keys (`reactions`, `resolved`) are never touched. Filter ARP threads by `thread.json` `.author` starting with `dd-agentic-review-platform`.

## Workflow — answering PR feedback

Write intent into the mirrored tree, then hand the human `timvisher_gh pr push`, which sends it in filename order and records what it sent so reruns never duplicate anything:

- Reply in a thread: create `<thread dir>/<UTC ts>-<slug>/comment.md` (`date -u +%FT%H-%M-%S%z` for the timestamp).
- New top-level comment: create `.timvisher_gh/pr/comments/<UTC ts>-<slug>/comment.md`.
- Edit your own posted comment: edit its `.md`; it is re-pushed under a lease on `posted.body`.
- React: add `"reactions": ["+1"]` to the item's JSON (REST names, emoji, or GraphQL enums are accepted).
- Resolve a thread: set `"resolved": true` in its `thread.json` (e.g. every ARP thread once addressed).

## Workflow — posting a PR comment

Write the comment body to a file (e.g. `comment.md`), then post it:

```bash
timvisher_gh comment comment.md                                    # PR URL from .timvisher_gh/pr/pr.json or Chrome
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

## Hooks and canned comments

Org-, repo- and path-specific steps (ARP review kicks, readiness gates, release watchers) are hooks, not ad hoc scripts: executables under `timvisher_gh.config/<scope>/pr/<push|ready|merge>/{pre,post}.d/` in either config root (`bash/bin/timvisher_gh.config/` in this repo, or `~/.config/timvisher/ide/bash/bin/timvisher_gh.config/`). `<scope>` is `orgs/OWNER`, `repos/OWNER/REPO`, or `repos/OWNER/REPO/paths/<dir>` (fires only when the PR touches `<dir>`). Pre-hooks gate a transition and are skipped once it has happened; post-hooks run every time and must check their own end state. `timvisher_gh --help` lists the environment they receive.

`timvisher_gh comment <name>` posts the canned comment `timvisher_gh.config/comments/<name>.md` when `<name>` is not a file (e.g. `timvisher_gh comment arp-review`).

## General GitHub interactions

When interacting with GitHub (github.com), always use the `gh` CLI. This includes viewing PRs, checking CI status, browsing releases, and querying repo metadata.

## Notes
- **No hard line breaks in paragraphs.** Write each paragraph as a single long line. Let the renderer or editor handle wrapping. Only use line breaks for list items, headings, code blocks, and between paragraphs (blank lines).
- Prefer `<=`/`<` comparisons in any pseudocode or scripts.
- `pr.md` and `issue.md` are always ignored; never offer to add or commit them.
