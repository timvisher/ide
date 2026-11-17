#!/usr/bin/env bash

# Where timvisher_git keeps its bare trunks, for every tool that needs to
# find one (timvisher_git, the git wrapper, ntmux3, fsmonitor cleanup, the
# system extensions' review tools).
#
# A trunk is not a cache: the worktrees made from it keep their commits,
# stashes, reflogs and admin files in it, so it can hold the only copy of
# unpushed work. It lives under XDG_DATA_HOME, not ~/.cache, which XDG
# lets anything delete, and which some hosts keep on storage that doesn't
# survive a restart. Only this root is ever looked in: trunks left at the
# old one are moved by a one-time 'timvisher_git migrate-trunks', not
# found there.
#
# Pure bash on purpose: the git wrapper sources this on every git command.

timvisher_git_trunks_root() {
  printf '%s\n' "${TIMVISHER_GIT_TRUNKS_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/timvisher_git/repo_trunks}"
}

timvisher_git_trunk_dir() {
  printf '%s\n' "$(timvisher_git_trunks_root)/$1/$2"
}

timvisher_git_trunks_each() {
  local dir
  for dir in "$(timvisher_git_trunks_root)"/*/*
  do
    [[ -d $dir ]] && printf '%s\n' "$dir"
  done
}

# <org>/<repo> when <common dir> is a managed trunk (or inside one), else
# exit 1. Compared resolved: the root may sit behind a symlink (macOS
# /private, a symlinked HOME, a root adopted onto another volume).
timvisher_git_trunk_relpath() {
  local dir=$1 resolved root rel
  resolved=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  root=$(cd "$(timvisher_git_trunks_root)" 2>/dev/null && pwd -P) || return 1
  [[ $resolved == "$root"/* ]] || return 1
  rel=${resolved#"$root"/}
  [[ $rel == */* ]] || return 1
  local rest=${rel#*/}
  printf '%s\n' "${rel%%/*}/${rest%%/*}"
}
