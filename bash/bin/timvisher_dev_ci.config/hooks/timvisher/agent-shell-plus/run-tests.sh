#!/usr/bin/env bash
# Repo rung (my repo) hook: applies to every branch under
# <my-github-user>/agent-shell-plus.  The rung walk resolves this rung as
# <me>/<repo>/ — for this user that's timvisher/agent-shell-plus/.

cd "$(git rev-parse --show-toplevel)" || exit 1

# Confirm an `upstream` remote is configured. Branches in this repo
# typically need to push to upstream during integration; bailing here
# surfaces a missing remote before tests run rather than after a failed
# `git push`.
git remote -v show upstream || exit 1

git_home=${TIMVISHER_GIT_HOME:-${HOME}/git}

# acp.el comes from xenodium, not the acp.el-plus fork: the fork is 0.11.3
# against agent-shell's 0.17.1 floor, and its one functional commit (asserting
# Terminal and Meta capability) is unused here. Against the fork the suite
# fails 27 tests; against xenodium it fails none.
# Real git ahead of the wrapper, for this hook only. Four agent-shell-worktree
# tests shell out to `git commit` in throwaway fixtures and the wrapper
# rejects them with git_commit_no_message -- it polices the agent's commits to
# real repositories, which a test fixture's commits to a temp dir are not.
# Verified both ways: 4 failures under the wrapper, 4 passes with the real
# binary. Excluding the tests instead would lose the coverage, and tolerating
# their failure would mean a list that goes stale and still reports green when
# they break for some other reason.
echo "--- bin/test (byte-compile, ERT, README check) ---"
PATH="$(brew --prefix)/bin:${PATH}" \
  shell_maker_root="${git_home}/xenodium/shell-maker/main" \
  acp_root="${git_home}/xenodium/acp.el/main" \
  bin/test || exit 1
