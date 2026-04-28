#!/usr/bin/env bash
# Level 2 (my repo) hook: applies to every branch under
# timvisher-dd/agent-shell-plus.  Replaces the per-branch Level 3
# hooks under xenodium/agent-shell-plus/<branch>/ that were drifting
# in formatting but did the same thing.

cd "$(git rev-parse --show-toplevel)" || exit 1

git_home=${TIMVISHER_GIT_HOME:-${HOME}/git}

echo "--- bin/test (byte-compile, ERT, README check) ---"
shell_maker_root="${git_home}/xenodium/shell-maker/main" \
  acp_root="${git_home}/timvisher-dd/acp.el-plus/main" \
  bin/test || exit 1
