#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)" || exit 1

git_home=${TIMVISHER_GIT_HOME:-${HOME}/git}
shell_maker_root="${git_home}/xenodium/shell-maker/main" acp_root="${git_home}/timvisher-dd/acp.el-plus/main" bin/test || exit 1
