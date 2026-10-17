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

`pr push` converges GitHub to the worktree and is safe to rerun after any failure: it pushes the branch (or reports "already pushed"), creates a draft PR from `pr.md` if none is recorded (adopting an existing open PR for the branch instead of duplicating it), and otherwise updates the title and body from `pr.md`. The URL is recorded in `.timvisher_gh/pr/pr.json`. `--force-with-lease` runs `git push --force-with-lease --force-if-includes`; `--force-with-lease=<sha>` leases against a specific remote SHA. `--open` opens the PR afterwards. `timvisher_gh -C <path> pr push` resolves the worktree from `<path>` instead of the current directory (`-C` goes before the subcommand), so one command works from anywhere.

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

Mirrors the whole conversation into `.timvisher_gh/pr/comments/` as `<name>.md` + `<name>.md.json` pairs in the same sidecar schema and naming the `comment` verbs use (`<name>` = `<ts>-<author>-<slug>`, `<ts>` the item's UTC creation time, so `ls` order is chronological): issue comments and reviews with a body at the top level, each review thread as a `<ts>-<author>-<path>-L<line>-thread/` directory holding its root comment (with `thread_id`, `path`, `line`, starting review and resolved state) and its replies. Safe to rerun: remote edits flow down, your unpushed edits to your own comments are kept, and intent keys (`reactions`, `resolved`) are never touched. Root `x.*.md` files tracking a comment on the PR move into the tree. Filter ARP threads by the root comment's `.author` starting with `dd-agentic-review-platform`.

## Workflow — answering PR feedback

Write intent into the mirrored tree, then hand the human `timvisher_gh pr push`, which sends it in filename order and records what it sent so reruns never duplicate anything:

- Reply in a thread: create `<thread dir>/<UTC ts>-<you>-<slug>.md` (`date -u +%FT%H-%M-%S%z` for the timestamp); it is posted with `comment reply`.
- New top-level comment: create `.timvisher_gh/pr/comments/<UTC ts>-<you>-<slug>.md`; it is posted with `comment`.
- Edit your own posted comment: edit its `.md`; it is re-pushed with `comment edit`, under its lease on `posted.body`.
- React: add `"reactions": ["+1"]` to the item's `.md.json` (any spelling `comment react` accepts).
- Resolve a thread: set `"resolved": true` in its root comment's `.md.json` (e.g. every ARP thread once addressed).

Starting new review threads and editing review bodies aren't supported.

## Workflow — working with PR comments

`timvisher_gh comment` tracks each comment as a file plus a `<file>.json` sidecar, the source of truth (kind, IDs, URL, author, thread, and what was last posted). `<file>.url` is regenerated from it for convenience, and a legacy `<file>.url` on its own is adopted into `<file>.json` the first time it's used. `timvisher_gh` resolves files from the repository root, so run these from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

A `<target>` is either a comment URL or a tracked file. A URL is `https://github.com/O/R/pull/N`, optionally followed by `/files` or `/changes` and a `?query` (as in notification links), ending in `#discussion_r<ID>` (review comment) or `#issuecomment-<ID>` (top-level comment). The PR itself and review summaries aren't comments, so these verbs don't act on them.

Rerunning a verb converges instead of repeating it: a tracked comment isn't posted twice, a repeated reaction isn't sent again, and resolving a resolved thread is harmless. Reruns ask GitHub who you are, so they need network access. Verbs print the comment's URL on stdout (`get` prints the file it wrote; `delete` prints nothing) and exit non-zero if anything didn't converge, so rerun the same command after fixing the cause. If a post succeeds but its state can't be recorded, the URL is printed with an error; save it in `<file>.url` before rerunning. Only github.com is supported, not GitHub Enterprise hosts.

### Post a top-level comment

```bash
timvisher_gh comment comment.md                                    # PR URL from .timvisher_gh/pr/pr.json or Chrome
timvisher_gh comment --pull-request=https://github.com/o/r/pull/1 comment.md  # explicit PR URL
```

Running it again when `comment.md.json` exists prints the URL instead of posting a duplicate. A file already posted on another PR, or one fetched with `get` (someone else's comment), is refused.

### Reply to a review comment

```bash
timvisher_gh comment reply 'https://github.com/o/r/pull/1#discussion_r123456' reply.md
timvisher_gh comment reply their-comment.md reply.md --reaction +1   # tracked target; react to it too
```

Only review comments (`#discussion_r<ID>`) have threads to reply in; replying to a reply posts in its thread. One reply file is one reply: a file already posted in another thread, a top-level comment's file, or a file fetched with `get` is refused. `--pull-request` only applies to posting. `--reaction` (repeatable) reacts to the comment being replied to. A reply whose `reply.md.json` exists isn't posted again.

### Edit a posted comment

```bash
timvisher_gh comment edit comment.md
timvisher_gh comment edit --force comment.md   # overwrite GitHub's copy anyway
```

Edits are leased: if GitHub's copy no longer matches what was last posted (someone else edited it), `edit` prints a diff and refuses. Fold their changes into the file, then rerun with `--force`. The check is a read just before the update, not an atomic swap, so an edit landing in between can still be overwritten. A file adopted from a legacy `.url` has no recorded body yet, so its first edit isn't leased.

### React to a comment

```bash
timvisher_gh comment react 'https://github.com/o/r/pull/1#issuecomment-123456' --reaction rocket --reaction 👀
timvisher_gh comment react --delete their-comment.md --reaction rocket
```

A reaction is a REST name (`+1`, `-1`, `laugh`, `confused`, `heart`, `hooray`, `rocket`, `eyes`), the matching emoji (👍 👎 😄 😕 ❤️ 🎉 🚀 👀, without skin tones), or a GraphQL `ReactionContent` name. Adding a reaction you've already made, or deleting one you haven't, is a no-op. A tracked target records your reactions in `posted.reactions`.

### Resolve a review thread

```bash
timvisher_gh comment resolve 'https://github.com/o/r/pull/1#discussion_r123456'
timvisher_gh comment resolve --unresolve their-comment.md
```

### Fetch someone else's comment

```bash
timvisher_gh comment get 'https://github.com/o/r/pull/1#discussion_r123456'           # picks the name
timvisher_gh comment get 'https://github.com/o/r/pull/1#discussion_r123456' their.md  # or name it
timvisher_gh comment get their.md                                                     # refresh it
```

Without a file name, `get` names it `<ts>-<author>-<slug>.md`:
- `<ts>` is the creation time GitHub reports (UTC on github.com) as `+%FT%H-%M-%S%z`.
- `<author>` is the login with anything but letters, digits and `-` turned into `-`, runs of `-` collapsed and ends trimmed, so `github-actions[bot]` becomes `github-actions-bot`.
- `<slug>` comes from the body. Control characters and `/` become spaces, whitespace runs collapse to one space, and leading spaces, `.` and `-` are dropped, as are trailing spaces and `.`. The result is cut to 60 characters and to fit a 255-byte file name. The fetched file is a tracked target for `reply`, `react` and `resolve`. Fetching the same comment again reuses that file, even after the comment's body changes. Refreshing keeps local edits you haven't pushed, along with their lease, so `edit` still notices if GitHub's copy changed meanwhile.

### Delete a comment

```bash
timvisher_gh comment delete comment.md          # prompts first
timvisher_gh comment delete --force comment.md  # batch cleanup
```

`--force` refuses comments someone else wrote, such as ones fetched with `get`; delete those interactively. A comment counts as already gone only when GitHub says so (404/410) and its repository is still reachable; any other failure keeps the state and exits non-zero.

## Workflow — merging and releasing

Agents do not merge. Hand the human one of:

```bash
timvisher_gh pr release              # merge, then watch the release via merge post-hooks
timvisher_gh pr release --no-watch   # merge only (same as `timvisher_gh pr merge`)
timvisher_gh pr merge                # the lower-level merge step
```

Both are idempotent: an already-merged PR reports "already merged in <commit>", an already-requested merge (auto-merge, merge queue, or a `/merge` comment since the last push) goes straight to waiting, and nothing is ever requested twice. After a confirmed merge, `timvisher_gh` drops `.timvisher_gh/pr/merged` and pulls the trunk worktree (`~/git/<org>/<repo>/<default branch>`) in the background. `--open` opens the PR, merge queue, and whatever the hooks discover.

## Hooks and canned comments

Org-, repo- and path-specific steps (ARP review kicks, readiness gates, release watchers) are hooks, not ad hoc scripts: executables under `timvisher_gh.config/<scope>/pr/<push|ready|merge>/{pre,post}.d/` in either config root (`bash/bin/timvisher_gh.config/` in this repo, or `~/.config/timvisher/ide/bash/bin/timvisher_gh.config/`). `<scope>` is `orgs/OWNER`, `repos/OWNER/REPO`, or `repos/OWNER/REPO/paths/<dir>` (fires only when the PR touches `<dir>`). Pre-hooks gate a transition and are skipped once it has happened; post-hooks run every time and must check their own end state. `timvisher_gh --help` lists the environment they receive.

`timvisher_gh comment <name>` posts the canned comment `timvisher_gh.config/comments/<name>.md` when `<name>` is not a file (e.g. `timvisher_gh comment arp-review`).

## General GitHub interactions

When interacting with GitHub (github.com), always use the `gh` CLI. This includes viewing PRs, checking CI status, browsing releases, and querying repo metadata.

## Account selection

`gh` on `PATH` is a shim that picks the gh account for each call, so the same command works across orgs that only one of several accounts (e.g. a personal account and an enterprise-managed one) can see. Don't set `GH_TOKEN` or switch accounts yourself.

**The account comes from exactly one of these, in order:**

1. `-R`/`--repo` before the subcommand: `gh -R OWNER/REPO pr view 5`, `gh -R OWNER gist list`, `gh -R OWNER api user`. The shim removes it and sets `GH_REPO` from an `OWNER/REPO` value.
2. For `gh api`, an endpoint right after `api` that starts with `repos/OWNER/`, `orgs/OWNER` or `users/OWNER`.
3. `GH_REPO`.
4. The cwd's github.com remotes, when they all name the same owner.

Otherwise the call stops with `gh_target_required`, as does any flag before the subcommand other than `-R`/`--repo`, `-h`, `--help` and `--version`. The account for an owner is in `timvisher_gh.config/orgs/<owner>/account`; with no mapping, gh's active account is used.

**The shim doesn't work out what gh will target beyond that.** If a call targets something other than the cwd's repo, such as a PR URL in another org, pass `-R` before the subcommand. A `gh_target_mismatch` notice appears when a github.com URL or `gh api` path in the call names a different owner; the call still runs.

- **`gh repo view|clone|fork|...` ignore `GH_REPO`.** Pass the repository as the argument too: `gh -R OWNER/REPO repo view OWNER/REPO`.
- **Each selecting call prints an aictl instruction** to stderr (`gh_account_selected` or `gh_account_active`). Don't merge gh's stderr into output you parse.
- **A mapped account without a token stops the call** with `gh_account_token_unavailable`.
- **A `GH_TOKEN` or `GITHUB_TOKEN` already in the environment wins**, with a `gh_account_deferred` notice.
- **`gh auth`, `config`, `alias`, `extension`, `help`, `completion` and `version` pass straight through.**
- **Help:** `-h`/`--help` as the last argument (or before the subcommand) runs `gh help <command> ...` and nothing else.
- **The agent guard blocks `-f`/`-F`**, so agents can't send GraphQL queries through `gh api` that way.

## Notes
- **No hard line breaks in paragraphs.** Write each paragraph as a single long line. Let the renderer or editor handle wrapping. Only use line breaks for list items, headings, code blocks, and between paragraphs (blank lines).
- Prefer `<=`/`<` comparisons in any pseudocode or scripts.
- `pr.md` and `issue.md` are always ignored; never offer to add or commit them.
