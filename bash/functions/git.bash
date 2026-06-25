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
# its own path). Walks PATH in order, dedupes by realpath, finds the entry
# matching the caller, and returns the one after it. Returns 1 if the caller
# isn't found or there is no next entry.
resolve_next_on_path() {
  local cmd="$1"
  local my_path="$2"
  my_path=$(realpath "$my_path" 2>/dev/null) || my_path="$2"

  local -a candidates=()
  local -A seen=()

  local -a _resolve_next__path_entries
  local dir candidate resolved
  IFS=: read -ra _resolve_next__path_entries <<< "$PATH"
  for dir in "${_resolve_next__path_entries[@]}"
  do
    candidate="$dir/$cmd"
    if [[ -x "$candidate" ]]
    then
      resolved=$(realpath "$candidate" 2>/dev/null) || resolved="$candidate"
      if [[ -z "${seen[$resolved]:-}" ]]
      then
        seen[$resolved]=1
        candidates+=("$resolved")
      fi
    fi
  done

  local found_self=false
  local path
  for path in "${candidates[@]}"
  do
    if [[ "$path" == "$my_path" ]]
    then
      found_self=true
      continue
    fi
    if [[ "$found_self" == true ]]
    then
      echo "$path"
      return 0
    fi
  done

  return 1
}

# git convenience wrapper (backward-compatible).
resolve_next_git() {
  resolve_next_on_path git "$1"
}
