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

### 5) Create or update the PR
Agents push draft PRs themselves, and nothing else:

```bash
timvisher_gh pr          # sync: pull the conversation, then push the branch and description
timvisher_gh pr push     # push only
```

The first push creates a draft PR from `pr.md` (`--ready-for-review` for a ready one, `--base <branch>` for a base other than the default branch), moves `pr.md` into the store and leaves a `pr.md` symlink to it; later runs push the branch (through `timvisher_git push`) and the title, body, draft state and base. `--draft`, `--ready-for-review` and `--base` are remembered and re-applied. Every write is safe to rerun after any failure. `--plan` shows what it would do and changes nothing. `--open` opens the PR afterwards. `timvisher_gh -C <path> pr` resolves the worktree from `<path>` (`-C` goes before the noun).

Under an agent, `timvisher_gh` creates a PR only as a draft and pushes only a draft PR for this worktree's branch. It fetches the PR fresh and grants `timvisher_git push` exactly that one push, which the git wrapper lets through; a plain `git push` is still blocked. If nobody else has pushed to the PR since `timvisher_gh` last did, a rewrite goes out without comparing content (a branch that's behind still stops); if someone has, only a fast-forward or a rewrite with the same changes does, and anything else stops for Tim. Marking a PR ready (`--ready-for-review`, `pr ready`), `pr merge` and `pr release` are refused: hand Tim the one-line invocation.

Changes are three-way: against what was last pushed or agreed, yours and GitHub's. Yours only is pushed; GitHub's only is pulled into your file by `pull` and the bare sync, and refused by `push` (exit 4: pull first). Both, differently, is a decision: exit 3 with the exact reruns for `--ours` (push yours), `--theirs` (take GitHub's) and `--merge` (`git merge-file`). Never write ad hoc `y.*.sh` push scripts; everything they did is a rerun.

## Where things live

`timvisher_gh` keeps every PR, issue and comment it knows in a store, `${XDG_DATA_HOME:-~/.local/share}/timvisher_gh/github.com/OWNER/REPO/pull/N/` (and `issues/N/`), with a state database beside it. A worktree's `.timvisher_gh/pr` is a symlink to its PR's store directory. Read anything about an object through `info`, never by parsing files:

```bash
timvisher_gh pr info                    # the worktree's PR, as JSON
timvisher_gh pr info .url               # one field, jq -r style
timvisher_gh pr info <url> .state       # open, closed or merged
timvisher_gh pr info --schema-version 1 .url   # in scripts: pin the record's contract
timvisher_gh pr info --help             # every field
```

`issue info`, `comment info` and `thread info` work the same way. `info` reads the state and fetches only objects it doesn't know yet; `timvisher_gh pr fetch` refreshes. A `<target>` is a github.com PR, issue or comment URL (optionally with `/files`, `/changes`, `/commits`, a `?query` or a `#fragment`), `current-browser-tab`, or a tracked file; with none, it's the worktree's PR.

## Workflow — creating an issue

Draft `issue.md` using the same format (title on line 1, blank line 2, body from line 3), then run:

```bash
timvisher_gh issue
```

It works like `pr`: created on the first sync, `issue.md` moved into the store, later edits synced, `timvisher_gh issue info .url` for the URL. `timvisher_gh issue pull` also mirrors the issue's comments into its store directory under `comments/`, and `timvisher_gh comment` posts, edits, reacts to and deletes them as it does a PR's.

## Workflow — marking a PR ready for review

Tim's step: agents are refused it. Wait for CI checks to pass, then remove draft status:

```bash
timvisher_gh pr ready
```

- Reports "already ready" (and runs only the ready post-hooks) when the PR is not a draft
- Polls `gh pr checks` until all non-excluded checks pass, runs the ready pre-hooks (e.g. an ARP gate), then marks the PR ready
- Fails immediately if any check has `bucket == "fail"`
- Org and repo exclude patterns at `timvisher_gh.config/{orgs/OWNER,repos/OWNER/REPO}/pr/ready/exclude-checks.txt` (either config root) ignore meta-checks (like mergegate) that never complete until all other checks pass
- One regex pattern per line; `#` comments and blank lines are skipped
- Override the default 10-second poll interval with `TIMVISHER_GH_PR_READY_POLL_INTERVAL`
- A PR that still reports no checks at all after 60 seconds (`TIMVISHER_GH_PR_READY_NO_CHECKS_GRACE`) is treated as having none and marked ready, so a repo without CI doesn't wait forever

## Workflow — reading PR feedback

```bash
timvisher_gh pr pull
```

Mirrors the whole conversation into the PR's store directory (`.timvisher_gh/pr/`): top-level comments under `comments/<ts>-<author>-<slug>/comment.md`, each review thread under `threads/<ts>-<author>-<path>-L<line>/` with its `root-comment.md` and `replies/<ts>-<author>-<slug>/comment.md`, and reviews under `reviews/` (read-only). Each object's `<kind>.json` beside it is its record. Safe to rerun: GitHub's edits flow into files you haven't changed, your unpushed edits to your own comments are kept and reported, and other people's comments are read-only. Filter ARP threads by the root comment's author starting with `dd-agentic-review-platform`.

## Workflow — answering PR feedback

Hand the human the command; each is safe to rerun and never posts twice:

```bash
timvisher_gh comment reply '<thread or review comment URL>' reply.md   # reply in that thread
timvisher_gh comment note.md                     # a top-level comment on the worktree's PR
timvisher_gh comment '<PR URL>' note.md          # ... on another PR
timvisher_gh comment '<issue URL>' note.md       # ... on an issue (its comments work the same as a PR's)
timvisher_gh comment push .timvisher_gh/pr/comments/<name>/comment.md   # after editing your own posted comment
timvisher_gh comment react '<comment URL>' +1 rocket                    # add reactions (--delete removes)
timvisher_gh thread resolve '<thread URL>'                              # --unresolve reopens
timvisher_gh thread '<PR URL>' nit.md --path pkg/a.go --line 12         # a new review thread
```

A posted file moves into the store and leaves a symlink, so editing the same path and rerunning updates the comment. `--reaction R` on `comment` or `comment reply` reacts to the target comment. A reaction is a REST name (`+1`, `-1`, `laugh`, `confused`, `heart`, `hooray`, `rocket`, `eyes`), the matching emoji (👍 👎 😄 😕 ❤️ 🎉 🚀 👀, without skin tones), or a GraphQL `ReactionContent` name. A thread is addressed by its root comment's `#discussion_r<ID>` URL. Editing review bodies isn't supported.

### Delete a comment

```bash
timvisher_gh comment delete '<comment URL>'          # prompts first
timvisher_gh comment delete --force '<comment URL>'  # your own comments only
```

`--force` refuses comments someone else wrote; delete those interactively. Our copy is archived once GitHub confirms the comment is gone.

## Workflow — merging and releasing

Agents do not merge. Hand the human one of:

```bash
timvisher_gh pr release              # merge, then watch the release via merge post-hooks
timvisher_gh pr release --no-watch   # merge only (same as `timvisher_gh pr merge`)
timvisher_gh pr merge                # the lower-level merge step
```

Both are idempotent: an already-merged PR reports "already merged in <commit>", an already-requested merge (auto-merge, merge queue, or a `/merge` comment since the last push) goes straight to waiting, and nothing is ever requested twice. After a confirmed merge, `timvisher_gh` records it (`timvisher_gh pr info .state` is `merged`) and pulls the trunk worktree (`~/git/<org>/<repo>/<default branch>`) in the background. `--open` opens the PR, merge queue, and whatever the hooks discover.

## Hooks and canned comments

Org-, repo- and path-specific steps (ARP review kicks, readiness gates, release watchers) are hooks, not ad hoc scripts: executables under `timvisher_gh.config/<scope>/pr/<push|ready|merge>/{pre,post}.d/` in either config root (`python/bin/timvisher_gh.config/` in this repo, or `~/.config/timvisher/ide/python/bin/timvisher_gh.config/`). `<scope>` is `orgs/OWNER`, `repos/OWNER/REPO`, or `repos/OWNER/REPO/paths/<dir>` (fires only when the PR touches `<dir>`). Pre-hooks gate a transition and are skipped once it has happened; post-hooks run every time and must check their own end state. They receive `TIMVISHER_GH_PHASE`, `_HOOK`, `_REPO`, `_PR_URL`, `_PR_NUMBER`, `_HEAD_SHA`, `_WORKTREE`, `_STATE_DIR` (the PR's store directory), `_MERGE_COMMIT`, `_NOTIFY_TITLE`, `_OPEN` and `_PATH_SCOPE`.

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
- **Each selecting call tells a listening agent which account it used** with an aictl instruction (`gh_account_selected` or `gh_account_active`): JSON on stderr under `TIMVISHER_AGENT`, and always in `TIMVISHER_AICTL_LOG` when that is set. With neither set, nothing is printed; with only the log set, stderr gets it as text. Don't merge gh's stderr into output you parse: it may be text, not JSON.
- **A mapped account without a token stops the call** with `gh_account_token_unavailable`.
- **A `GH_TOKEN` or `GITHUB_TOKEN` already in the environment wins**, with a `gh_account_deferred` notice.
- **`gh auth`, `config`, `alias`, `extension`, `help`, `completion` and `version` pass straight through.**
- **Help:** `-h`/`--help` as the last argument (or before the subcommand) runs `gh help <command> ...` and nothing else.
- **The agent guard blocks `-f`/`-F`**, so agents can't send GraphQL queries through `gh api` that way.

## Notes
- **No hard line breaks in paragraphs.** Write each paragraph as a single long line. Let the renderer or editor handle wrapping. Only use line breaks for list items, headings, code blocks, and between paragraphs (blank lines).
- Prefer `<=`/`<` comparisons in any pseudocode or scripts.
- `pr.md` and `issue.md` are always ignored; never offer to add or commit them.
