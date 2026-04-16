#!/usr/bin/env bash

# Resolves the next `git` binary in PATH after the caller.
#
# Used by git wrapper scripts that form a chain:
#   ~/.config/timvisher/ide/bash/bin/git → ~/bin/git → $(brew --prefix)/bin/git → /usr/bin/git
#
# Each wrapper sources this, calls resolve_next_git with its own path,
# and gets back the next git in the chain.
#
# Usage:
#   source ~/.functions/git.bash
#   next_git=$(resolve_next_git "${BASH_SOURCE[0]}")
#   "$next_git" "$@"

resolve_next_git() {
  local my_path="$1"
  my_path=$(realpath "$my_path" 2>/dev/null) || my_path="$1"

  # Deduplicate and collect all git binaries in PATH order
  local -a gits=()
  local -A seen=()

  local -a _resolve_next_git__path_entries
  local dir candidate resolved
  IFS=: read -ra _resolve_next_git__path_entries <<< "$PATH"
  for dir in "${_resolve_next_git__path_entries[@]}"
  do
    candidate="$dir/git"
    if [[ -x "$candidate" ]]
    then
      resolved=$(realpath "$candidate" 2>/dev/null) || resolved="$candidate"
      if [[ -z "${seen[$resolved]:-}" ]]
      then
        seen[$resolved]=1
        gits+=("$resolved")
      fi
    fi
  done

  # Find myself, return the next one
  local found_self=false
  local git_path
  for git_path in "${gits[@]}"
  do
    if [[ "$git_path" == "$my_path" ]]
    then
      found_self=true
      continue
    fi
    if [[ "$found_self" == true ]]
    then
      echo "$git_path"
      return 0
    fi
  done

  return 1
}
