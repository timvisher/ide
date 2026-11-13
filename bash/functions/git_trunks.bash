#!/usr/bin/env bash

# Where timvisher_git keeps its bare trunks, for every tool that needs to
# find one (timvisher_git, the git wrapper, ntmux3, fsmonitor cleanup, the
# system extensions' review tools).
#
# A trunk is not a cache: the worktrees made from it keep their commits,
# stashes, reflogs and admin files in it, so it can hold the only copy of
# unpushed work. It lives under XDG_DATA_HOME, not ~/.cache, which XDG
# lets anything delete and a Datadog workspace wipes on every pause or
# restart. Trunks not yet moved by 'timvisher_git migrate-trunks' are still
# found at the old root; new trunks are always made at the new one.
#
# Pure bash on purpose: the git wrapper sources this on every git command.

timvisher_git_trunks_root() {
  printf '%s\n' "${TIMVISHER_GIT_TRUNKS_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/timvisher_git/repo_trunks}"
}

timvisher_git_legacy_trunks_root() {
  printf '%s\n' "${TIMVISHER_GIT_LEGACY_TRUNKS_DIR:-${HOME}/.cache/timvisher_git_worktrees/repo_trunks}"
}

# The trunk for <org> <repo>: at the new root if it is there, else at the
# old root if it is still there, else where a new one goes.
timvisher_git_trunk_dir() {
  local org=$1 repo=$2 root legacy
  root=$(timvisher_git_trunks_root)
  if [[ -d $root/$org/$repo ]]
  then
    printf '%s\n' "$root/$org/$repo"
    return 0
  fi
  legacy=$(timvisher_git_legacy_trunks_root)
  if [[ ! -L $legacy && -d $legacy/$org/$repo ]]
  then
    printf '%s\n' "$legacy/$org/$repo"
    return 0
  fi
  printf '%s\n' "$root/$org/$repo"
}

# Every trunk, one directory per line: the new root's, then the old
# root's that haven't been moved yet.
timvisher_git_trunks_each() {
  local root legacy dir
  root=$(timvisher_git_trunks_root)
  legacy=$(timvisher_git_legacy_trunks_root)
  for dir in "$root"/*/*
  do
    [[ -d $dir ]] && printf '%s\n' "$dir"
  done
  [[ -L $legacy ]] && return 0
  for dir in "$legacy"/*/*
  do
    [[ -d $dir && ! -d $root/${dir#"$legacy"/} ]] && printf '%s\n' "$dir"
  done
}

# <org>/<repo> when <common dir> is a managed trunk (or inside one), else
# exit 1. Paths are compared resolved, since either root may sit behind a
# symlink (macOS /private, a symlinked HOME).
timvisher_git_trunk_relpath() {
  local dir=$1 resolved root rel
  resolved=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  for root in "$(timvisher_git_trunks_root)" "$(timvisher_git_legacy_trunks_root)"
  do
    [[ -d $root ]] || continue
    root=$(cd "$root" && pwd -P) || continue
    if [[ $resolved == "$root"/* ]]
    then
      rel=${resolved#"$root"/}
      [[ $rel == */* ]] || continue
      local org=${rel%%/*} rest=${rel#*/}
      printf '%s\n' "$org/${rest%%/*}"
      return 0
    fi
  done
  return 1
}
