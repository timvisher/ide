#!/usr/bin/env bash

# The one resolver for wrappers that stand in for a real binary of the same
# name (claude, codex, gh, the system extensions' bzl, go, workspaces, ...).
#
#   real=$(timvisher_real_bin <name> <wrapper> [<dir>...]) || die ...
#   timvisher_real_bin_skip_self <wrapper>     # in the wrapper, before exec
#   exec "$real" "$@"
#
# timvisher_real_bin prints the first executable <name> among, in order:
#   1. <dir>/<name> for each <dir> given: the tool's preferred source
#      (bzl passes dogbrew's bin, which Datadog ships it through)
#   2. $(brew --prefix)/bin/<name>, when brew runs and that file exists
#   3. <name> in each PATH entry
# It skips anything whose realpath is <wrapper>, that sits in the
# wrapper's directory, or that sits in a directory listed in
# TIMVISHER_REAL_BIN_SKIP, so a wrapper never resolves to itself or to
# another copy of itself. It returns 1 when nothing is found.
#
# timvisher_real_bin_skip_self adds the wrapper's directory to the exported
# TIMVISHER_REAL_BIN_SKIP. With two checkouts of the wrappers on PATH (e.g.
# during a move of ~/git) each copy then skips the other instead of the two
# exec'ing each other.
#
# Wrappers find this file relative to themselves, so they work before
# ~/.functions is installed and from any checkout.

timvisher_real_bin_skip_self() {
  local self_real
  self_real=$(realpath "$1" 2>/dev/null) || self_real=$1
  export TIMVISHER_REAL_BIN_SKIP="${TIMVISHER_REAL_BIN_SKIP:+${TIMVISHER_REAL_BIN_SKIP}:}${self_real%/*}"
}

timvisher_real_bin() {
  local name=$1 self=$2
  shift 2
  local self_real self_dir prefix dir candidate candidate_real skip skipped
  local -a candidates=() path_entries=() skip_dirs=()

  self_real=$(realpath "$self" 2>/dev/null) || self_real=$self
  self_dir=${self_real%/*}

  for dir in "$@"
  do
    candidates+=("$dir/$name")
  done
  if command -v brew >/dev/null 2>&1 &&
       prefix=$(brew --prefix 2>/dev/null) &&
       [[ -n $prefix ]]
  then
    candidates+=("$prefix/bin/$name")
  fi
  IFS=: read -ra path_entries <<< "$PATH"
  for dir in "${path_entries[@]}"
  do
    [[ -n $dir ]] && candidates+=("$dir/$name")
  done

  IFS=: read -ra skip_dirs <<< "${TIMVISHER_REAL_BIN_SKIP-}"
  skip_dirs+=("$self_dir")

  for candidate in "${candidates[@]}"
  do
    [[ -f $candidate && -x $candidate ]] || continue
    candidate_real=$(realpath "$candidate" 2>/dev/null) || candidate_real=$candidate
    [[ $candidate_real == "$self_real" ]] && continue
    skipped=false
    for skip in "${skip_dirs[@]}"
    do
      if [[ -n $skip && ${candidate_real%/*} == "$skip" ]]
      then
        skipped=true
        break
      fi
    done
    [[ $skipped == true ]] && continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

# timvisher_real_bin_script_dirs <name> prints, ':'-separated for
# TIMVISHER_REAL_BIN_SKIP, the directory of every <name> on PATH that is a
# script (starts with '#!'). A real git, bash or gh is a binary, so this
# names every wrapper checkout on PATH, including ones the caller isn't, such
# as the installed ide's ~/bin/git seen from a worktree's tests.
timvisher_real_bin_script_dirs() {
  local name=$1 candidate dirs=
  while IFS= read -r candidate
  do
    [[ $(head -c 2 -- "$candidate" 2> /dev/null) == '#!' ]] || continue
    candidate=$(realpath -- "$candidate" 2> /dev/null) || continue
    dirs+=${dirs:+:}${candidate%/*}
  done < <(type -ap "$name")
  printf '%s\n' "$dirs"
}
