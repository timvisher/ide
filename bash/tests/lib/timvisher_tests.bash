#!/usr/bin/env bash

timvisher_tests_fresh_home() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/fresh_home.XXXXXX") || return 1
  /bin/cp -R "$TIMVISHER_TESTS_TEMPLATE" "$dir/home" || return 1
  # As timvisher_tests does for each suite's HOME: keep the global
  # config's hooks off the receiving side of local pushes.
  mkdir -p "$dir/home/.local/state/timvisher_tests/hooks" || return 1
  if [[ ! -e $dir/home/.gitconfig && ! -L $dir/home/.gitconfig ]]
  then
    printf '[core]\n\thooksPath = %s\n' "$dir/home/.local/state/timvisher_tests/hooks" \
      > "$dir/home/.gitconfig" || return 1
  fi
  export HOME=$dir/home
  export XDG_CONFIG_HOME=$HOME/.config
  export XDG_DATA_HOME=$HOME/.local/share
  export XDG_STATE_HOME=$HOME/.local/state
  export XDG_CACHE_HOME=$HOME/.cache
  export TIMVISHER_GIT_HOME=$HOME/git
}

timvisher_tests_with_home() {
  local home=$1
  shift
  HOME=$home \
    XDG_CONFIG_HOME=$home/.config \
    XDG_DATA_HOME=$home/.local/share \
    XDG_STATE_HOME=$home/.local/state \
    XDG_CACHE_HOME=$home/.cache \
    TIMVISHER_GIT_HOME=$home/git \
    "$@"
}
