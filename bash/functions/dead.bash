timvisher_dead() {
  local old_name=$1
  local replacement=${2:-}

  if [[ -z $old_name ]]
  then
    echo 'timvisher_dead: requires at least one argument (the dead command name)' >&2
    return 1
  fi

  # Auto-detect promoted name: strip _EXP_ if present and check if it exists
  if [[ -z $replacement && $old_name == *_EXP_* ]]
  then
    local candidate=${old_name/_EXP_/_}
    if type -t "$candidate" &>/dev/null
    then
      replacement=$candidate
    fi
  fi

  if [[ -n $replacement ]]
  then
    if type -t "$replacement" &>/dev/null
    then
      eval "${old_name}() { error '${old_name} replaced by ${replacement}'; return 1; }"
    else
      eval "${old_name}() { error '${old_name}: ${replacement}'; return 1; }"
    fi
  else
    eval "${old_name}() { error '${old_name} no longer defined'; return 1; }"
  fi
}
