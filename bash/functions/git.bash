#!/usr/bin/env bash

# Resolve the next executable of a given name in PATH after the caller, so a
# wrapper script can delegate to the real binary it shadows without invoking
# itself. Wrappers form a chain, e.g. for git:
#   ~/.config/timvisher/ide/bash/bin/git → ~/bin/git → $(brew --prefix)/bin/git → /usr/bin/git
#
# Usage:
#   source ~/.functions/git.bash
#   next=$(resolve_next_on_path gh "${BASH_SOURCE[0]}")   # generic
#   next_git=$(resolve_next_git "${BASH_SOURCE[0]}")      # git convenience
#   "$next" "$@"

# Generic: echo the next PATH executable named $1 after the caller ($2,
# its own path). Walks PATH in order, dedupes entries that are the same
# file, finds the entry matching the caller, and returns the one after it.
# Returns 1 if the caller isn't found or there is no next entry.
#
# Same-file checks use [[ -ef ]], not realpath: a realpath fork per PATH
# entry was most of a wrapped git call's startup.
resolve_next_on_path() {
  local cmd=$1 my_path=$2
  local -a candidates=() _resolve_next__path_entries
  local dir candidate seen found_self=false

  IFS=: read -ra _resolve_next__path_entries <<< "$PATH"
  for dir in "${_resolve_next__path_entries[@]}"
  do
    candidate=$dir/$cmd
    [[ -f $candidate && -x $candidate ]] || continue
    for seen in "${candidates[@]}"
    do
      [[ $candidate -ef $seen ]] && continue 2
    done
    candidates+=("$candidate")
    if [[ $candidate -ef $my_path ]]
    then
      found_self=true
    elif [[ $found_self == true ]]
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# git convenience wrapper (backward-compatible).
resolve_next_git() {
  resolve_next_on_path git "$1"
}
