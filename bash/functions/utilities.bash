maybe_continue() {
  local resp

  if [[ -n $timvisher_EXP_force ]]
  then
    info 'forcing a continue'
    return
  fi

  read -rp 'Continue? (y/N) ' resp

  if [[ $resp != y ]]
  then
    info Exiting
    exit
  fi
}
