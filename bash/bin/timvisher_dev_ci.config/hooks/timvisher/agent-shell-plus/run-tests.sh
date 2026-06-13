#!/usr/bin/env bash
# Level 2 (my repo) hook: applies to every branch under
# <my-github-user>/agent-shell-plus.  The cascade resolves Level 2 as
# ${gh_me}/${_wt_repo}/ — for this user that's timvisher/agent-shell-plus/.

cd "$(git rev-parse --show-toplevel)" || exit 1

# Confirm an `upstream` remote is configured. Branches in this repo
# typically need to push to upstream during integration; bailing here
# surfaces a missing remote before tests run rather than after a failed
# `git push`.
git remote -v show upstream || exit 1

git_home=${TIMVISHER_GIT_HOME:-${HOME}/git}

echo "--- bin/test (byte-compile, ERT, README check) ---"
shell_maker_root="${git_home}/xenodium/shell-maker/main" \
  acp_root="${git_home}/timvisher-dd/acp.el-plus/main" \
  bin/test || exit 1
