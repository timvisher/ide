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

## Workflow — working with PR comments

`timvisher_gh comment` tracks each comment as a file plus a `<file>.json` sidecar, the source of truth (kind, IDs, URL, author, thread, and what was last posted). `<file>.url` is regenerated from it for convenience, and a legacy `<file>.url` on its own is adopted into `<file>.json` the first time it's used. `timvisher_gh` resolves files from the repository root, so run these from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

A `<target>` is either a comment URL or a tracked file. A URL is `https://github.com/O/R/pull/N`, optionally followed by `/files` or `/changes` and a `?query` (as in notification links), ending in `#discussion_r<ID>` (review comment) or `#issuecomment-<ID>` (top-level comment). The PR itself and review summaries aren't comments, so these verbs don't act on them.

Rerunning a verb converges instead of repeating it: a tracked comment isn't posted twice, and repeated reactions and resolutions are no-ops. Verbs print the comment's URL on stdout (`get` prints the file it wrote; `delete` prints nothing) and exit non-zero if anything didn't converge, so rerun the same command after fixing the cause. If a post succeeds but its state can't be recorded, the URL is printed with an error; save it in `<file>.url` before rerunning. Only github.com is supported, not GitHub Enterprise hosts.

### Post a top-level comment

```bash
timvisher_gh comment comment.md                                    # PR URL from pr.md.url or Chrome
timvisher_gh comment --pull-request=https://github.com/o/r/pull/1 comment.md  # explicit PR URL
```

Running it again when `comment.md.json` exists prints the URL instead of posting a duplicate.

### Reply to a review comment

```bash
timvisher_gh comment reply 'https://github.com/o/r/pull/1#discussion_r123456' reply.md
timvisher_gh comment reply their-comment.md reply.md --reaction +1   # tracked target; react to it too
```

Only review comments (`#discussion_r<ID>`) have threads to reply in; replying to a reply posts in its thread. One reply file is one reply: a file already posted in another thread is refused. `--reaction` (repeatable) reacts to the comment being replied to. A reply whose `reply.md.json` exists isn't posted again.

### Edit a posted comment

```bash
timvisher_gh comment edit comment.md
timvisher_gh comment edit --force comment.md   # overwrite GitHub's copy anyway
```

Edits are leased: if GitHub's copy no longer matches what was last posted (someone else edited it), `edit` prints a diff and refuses. Fold their changes into the file, then rerun with `--force`. A file adopted from a legacy `.url` has no recorded body yet, so its first edit isn't leased.

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

Without a file name, `get` names it `<ts>-<author>-<slug>.md`: `<ts>` is the comment's UTC creation time as `+%FT%H-%M-%S%z`, and `<slug>` is the first 60 characters of the body with whitespace collapsed to single spaces. The fetched file is a tracked target for `reply`, `react` and `resolve`. Fetching the same comment again reuses that file, even after the comment's body changes. Refreshing keeps local edits you haven't pushed, along with their lease, so `edit` still notices if GitHub's copy changed meanwhile.

### Delete a comment

```bash
timvisher_gh comment delete comment.md          # prompts first
timvisher_gh comment delete --force comment.md  # batch cleanup
```

`--force` refuses comments someone else wrote, such as ones fetched with `get`; delete those interactively. A comment counts as already gone only when GitHub says so (404/410) and its repository is still reachable; any other failure keeps the state and exits non-zero.

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
