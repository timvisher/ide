#!/usr/bin/env bash

die() {
  printf "%s DIE %s: ${1}\n" "$(date -u '+%FT%T%z')" "${FUNCNAME[1]}" "${@:2}" >&2
  exit 1
}

info() {
  printf "%s INFO %s: ${1}\n" "$(date -u '+%FT%T%z')" "${FUNCNAME[1]}" "${@:2}" >&2
}

error() {
  printf "%s ERROR %s: ${1}\n" "$(date -u '+%FT%T%z')" "${FUNCNAME[1]}" "${@:2}" >&2
}

display_script() {
  info "Contents of ${1}"
  nl -n rz "$1" |
    while read -r l
    do
      info '%s' "$l"
    done
}

info_array() {
  if [[ $1 == *'%s'* ]]
  then
    for x in "${@:2}"
    do
      info "$1" "$x"
    done
  else
    for x in "$@"
    do
      info "$x"
    done
  fi
}

info_stdout() {
  if [[ $1 == *'%s'* ]]
  then
    msg=$1
  else
    msg='info stdout: ‘%s’'
  fi
  nl -n rz |
    while read -r l
    do
      info "$msg" "$l"
    done
}
