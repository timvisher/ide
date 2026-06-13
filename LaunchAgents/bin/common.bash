#!/usr/bin/env bash

# Shared helpers for the LaunchAgents/bin/* wrappers (start/stop/status/
# hup). Sourced, not executed.

# la_domain / la_dest / la_tree_dir are consumed by the scripts that
# source this file.
# shellcheck disable=SC2034

source "${HOME}/.functions/logging.bash" ||
  {
    echo "Unable to source logging functions" >&2
    exit 1
  }

command -v launchctl >/dev/null ||
  die "launchctl not found"

la_domain="gui/$(id -u)"
la_dest="${TIMVISHER_LAUNCHAGENTS_DIR:-${HOME}/Library/LaunchAgents}"

# The LaunchAgents/ directory that holds this bin/ -- the source of the
# managed *.plist files, resolved once relative to this script.
la_tree_dir=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)") ||
  die "couldn't resolve the LaunchAgents directory"

# la_source_plists [plist-or-label...]
#
# Print one source plist path per line. Arguments are resolved as: an
# existing *.plist path used as-is, otherwise a label whose plist is
# la_tree_dir/<label>.plist. With no arguments, every *.plist in
# la_tree_dir is emitted.
la_source_plists() {
  local a pf found=0
  if (( 0 < $# ))
  then
    for a in "$@"
    do
      if [[ $a == *.plist && -f $a ]]
      then
        printf '%s\n' "$a"
      else
        printf '%s\n' "${la_tree_dir}/$(basename "$a" .plist).plist"
      fi
    done
    return 0
  fi

  shopt -s nullglob
  for pf in "${la_tree_dir}"/*.plist
  do
    printf '%s\n' "$pf"
    found=1
  done
  shopt -u nullglob
  (( found )) ||
    die "no *.plist files in ‘%s’ and no arguments given" "$la_tree_dir"
}

# la_labels [label-or-plist...]
#
# Print one launchd label per line. With arguments, each is treated as a
# label (a trailing .plist is stripped, so plist paths work too). With no
# arguments, labels are derived from the *.plist files in la_tree_dir.
la_labels() {
  local a pf found=0
  if (( 0 < $# ))
  then
    for a in "$@"
    do
      basename "$a" .plist
    done
    return 0
  fi

  shopt -s nullglob
  for pf in "${la_tree_dir}"/*.plist
  do
    basename "$pf" .plist
    found=1
  done
  shopt -u nullglob
  (( found )) ||
    die "no *.plist files in ‘%s’ and no labels given" "$la_tree_dir"
}
