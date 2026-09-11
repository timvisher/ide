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
