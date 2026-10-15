#!/usr/bin/env bash

timvisher_path_prepend() {
  local dir=$1
  local var=${2:-PATH}
  local -a entries=()
  local -a kept=()
  local entry

  IFS=: read -ra entries <<< "${!var}"

  for entry in "${entries[@]}"
  do
    if [[ $entry != "$dir" ]]
    then
      kept=("${kept[@]}" "$entry")
    fi
  done

  local IFS=:
  export "$var=$dir${kept[*]:+:${kept[*]}}"
}

timvisher_path_prepend_ide_roots() {
  local root

  timvisher_path_prepend "$HOME/.local/bin"

  for root in "$@"
  do
    if [[ ! -d $root ]]
    then
      continue
    fi

    if [[ $HOME/bin -ef $root/bash/bin ]]
    then
      timvisher_path_prepend "$HOME/bin"
    else
      timvisher_path_prepend "$root/bash/bin"
    fi
    timvisher_path_prepend "$root/python/bin"
    timvisher_path_prepend "$root/python/lib" PYTHONPATH
  done
}
