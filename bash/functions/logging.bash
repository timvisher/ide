#!/usr/bin/env bash

# Log level configuration
# timvisher_logging_log_level can be set to: ERROR, WARN, INFO, TRACE
# If unset and CLAUDECODE or CODEX_SANDBOX is set, defaults to ERROR
# If unset and neither CLAUDECODE nor CODEX_SANDBOX is set, all levels are enabled
declare -gA timvisher_logging__levels=(
  [ERROR]=0
  [WARN]=1
  [INFO]=2
  [TRACE]=3
  [DIE]=0
)

# Arbitrary tagged data merged into structured log output.
# Set keys before calling log functions; they persist across calls.
# Clear with: timvisher_logging_data=()
declare -gA timvisher_logging_data

timvisher_logging__json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  printf '%s' "$s"
}

# Cache jq availability at source time
if command -v jq >/dev/null 2>&1
then
  timvisher_logging__has_jq=true
else
  timvisher_logging__has_jq=false
fi

timvisher_logging__should_log() {
  local level=$1
  local effective_log_level

  # Determine effective log level
  if [[ -z ${timvisher_logging_log_level:-} ]]
  then
    if [[ -n ${CLAUDECODE:-} || -n ${TIMVISHER_CODEX:-} || -n ${TIMVISHER_AGENT:-} ]]
    then
      # Default to ERROR when being executed by an agent
      effective_log_level=ERROR
    else
      # All levels enabled when not in Claude
      return 0
    fi
  else
    effective_log_level=${timvisher_logging_log_level}
  fi

  # Check if requested level should log
  local current_level_value=${timvisher_logging__levels[${effective_log_level}]}
  local requested_level_value=${timvisher_logging__levels[${level}]}

  # Treat unknown log levels as ERROR
  if [[ -z ${requested_level_value} ]]
  then
    requested_level_value=${timvisher_logging__levels[ERROR]}
  fi

  if [[ -z ${current_level_value} ]]
  then
    # Invalid current log level set, log everything
    return 0
  fi

  if (( requested_level_value <= current_level_value ))
  then
    return 0
  else
    return 1
  fi
}

timvisher_logging__log() {
  local level=${FUNCNAME[1]^^}

  # Check if should log (returns 0 for yes, 1 for no)
  if timvisher_logging__should_log "$level"
  then
    if [[ -n ${TIMVISHER_AGENT:-} ]]
    then
      local formatted_message
      # shellcheck disable=SC2059
      printf -v formatted_message "${1}" "${@:2}"

      if [[ $timvisher_logging__has_jq == true ]]
      then
        local -a jq_args=(
          --arg type log
          --arg level "$level"
          --arg caller "${FUNCNAME[2]:-main}"
          --arg message "$formatted_message"
        )
        local jq_filter='{type: $type, level: $level, caller: $caller, message: $message}'

        if (( 0 < ${#timvisher_logging_data[@]} ))
        then
          local -i di=0
          local key
          for key in "${!timvisher_logging_data[@]}"
          do
            jq_args+=(--arg "dk${di}" "$key" --arg "dv${di}" "${timvisher_logging_data[$key]}")
            ((di++))
          done
          local data_expr='{' first=true j
          for ((j=0; j<di; j++))
          do
            if [[ $first == true ]]
            then
              data_expr+="(\$dk${j}): \$dv${j}"
              first=false
            else
              data_expr+=", (\$dk${j}): \$dv${j}"
            fi
          done
          data_expr+='}'
          jq_filter+=" | .data = ${data_expr}"
        fi

        jq -n -c "${jq_args[@]}" "$jq_filter" >&2
      else
        # Fallback: printf-based JSON when jq is not available
        local escaped_message
        escaped_message=$(timvisher_logging__json_escape "$formatted_message")
        local json
        printf -v json '{"type":"log","level":"%s","caller":"%s","message":"%s"' \
          "$level" "${FUNCNAME[2]:-main}" "$escaped_message"

        if (( 0 < ${#timvisher_logging_data[@]} ))
        then
          json+=',"data":{'
          local first=true ek ev key
          for key in "${!timvisher_logging_data[@]}"
          do
            ek=$(timvisher_logging__json_escape "$key")
            ev=$(timvisher_logging__json_escape "${timvisher_logging_data[$key]}")
            if [[ $first == true ]]
            then
              json+="\"${ek}\":\"${ev}\""
              first=false
            else
              json+=",\"${ek}\":\"${ev}\""
            fi
          done
          json+='}'
        fi

        json+='}'
        printf '%s\n' "$json" >&2
      fi
    else
      # Format: timestamp LEVEL caller_function: message
      printf "%s %s %s: ${1}\n" "$(date -u '+%FT%T%z')" "$level" "${FUNCNAME[2]:-main}" "${@:2}" >&2
    fi
  fi
}

die() {
  timvisher_logging__log "$@"
  exit 1
}

info() {
  timvisher_logging__log "$@"
}

warn() {
  timvisher_logging__log "$@"
}

trace() {
  timvisher_logging__log "$@"
}

trace_v() {
  v=$1

  trace '%s: ‘%s’' "$v" "${!v}"
}

error_v() {
  v=$1

  error '%s: ‘%s’' "$v" "${!v}"
}

info_v() {
  v=$1

  info '%s: ‘%s’' "$v" "${!v}"
}

error() {
  timvisher_logging__log "$@"
}

f_assert_v() {
  v=$1

  [[ -n ${!v} ]] ||
    {
      error "Variable ‘%s’ is empty" "${v}"
      return 1
    }
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

trace_array() {
  if [[ $1 == *'%s'* ]]
  then
    for x in "${@:2}"
    do
      trace "$1" "$x"
    done
  else
    for x in "$@"
    do
      trace "$x"
    done
  fi
}

info_array_v() {
  local v=$1

  # https://mywiki.wooledge.org/BashFAQ/006#Evaluating_indirect.2Freference_variables
  local tmp=${v}[@]
  info_array "${v%s}: ‘%s’" "${!tmp}"
}

trace_array_v() {
  local v=$1

  # https://mywiki.wooledge.org/BashFAQ/006#Evaluating_indirect.2Freference_variables
  local tmp=${v}[@]
  trace_array "${v%s}: ‘%s’" "${!tmp}"
}

error_array() {
  if [[ $1 == *'%s'* ]]
  then
    for x in "${@:2}"
    do
      error "$1" "$x"
    done
  else
    for x in "$@"
    do
      error "$x"
    done
  fi
}

error_array_v() {
  local v=$1

  # https://mywiki.wooledge.org/BashFAQ/006#Evaluating_indirect.2Freference_variables
  local tmp=${v}[@]
  error_array "${v%s}: ‘%s’" "${!tmp}"
}

info_stdout() {
  local log_copy
  local stdout_copy
  if [[ $1 == *'%s'* ]]
  then
    msg=$1
  else
    msg='info stdout: ‘%s’'
  fi

  while IFS=$'\n' read -r l
  do
    log_copy+="${l}\n"
    stdout_copy+="${l}\n"
  done

  trace_v log_copy

  printf "$log_copy" |
    nl -n rz |
    while IFS=$'\n' read -r l
    do
      info "$msg" "$l"
    done
  printf "$stdout_copy"
}

error_stdout() {
  local log_copy
  local stdout_copy
  if [[ $1 == *'%s'* ]]
  then
    msg=$1
  else
    msg='error stdout: ‘%s’'
  fi

  while IFS=$'\n' read -r l
  do
    log_copy+="${l}\n"
    stdout_copy+="${l}\n"
  done

  trace_v log_copy

  printf "$log_copy" |
    nl -n rz |
    while IFS=$'\n' read -r l
    do
      error "$msg" "$l"
    done
  printf "$stdout_copy"
}
