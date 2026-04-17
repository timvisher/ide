#!/usr/bin/env bash

# aictl - Structured agent CLI messaging
#
# Functions for agent-aware guardrails following the principles from
# "Most CLIs are built for humans. Agents need more than that."
#
# Provides:
#   aictl_die  - Fatal error, always exits non-zero (not bypassable)
#   aictl_warn - Blocking warning, exits unless TIMVISHER_AGENT_NIRMI=1
#
# Output is JSON to stderr:
#   {"type":"instruction","level":"error|warning|bypass","code":"...","message":"...", ...}
#
# Both functions accept --flag arguments for rich fields:
#   --code, --message, --reason, --doc, --suggestion, --command
#
# Positional fallback: <code> <message> [suggestion...]
#
# Environment:
#   TIMVISHER_AGENT_NIRMI=1  Bypass aictl_warn guards

_aictl_loaded=true

aictl__json_escape() {
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

# Parse --flag args into variables. Sets: _code, _message, _reason,
# _doc, _command, _suggestions array.
aictl__parse_args() {
  _code=""
  _message=""
  _reason=""
  _doc=""
  _command=""
  _suggestions=()

  while (( 0 < $# ))
  do
    case "$1" in
      --code) _code=$2; shift 2 ;;
      --message) _message=$2; shift 2 ;;
      --reason) _reason=$2; shift 2 ;;
      --doc) _doc=$2; shift 2 ;;
      --command) _command=$2; shift 2 ;;
      --suggestion) _suggestions+=("$2"); shift 2 ;;
      --)
        shift
        _suggestions+=("$@")
        break
        ;;
      *)
        # Positional fallback: code, message, then suggestions
        if [[ -z $_code ]]; then
          _code=$1
        elif [[ -z $_message ]]; then
          _message=$1
        else
          _suggestions+=("$1")
        fi
        shift
        ;;
    esac
  done
}

aictl__emit() {
  local level=$1
  shift

  aictl__parse_args "$@"

  local escaped_message
  escaped_message=$(aictl__json_escape "$_message")

  printf '{"type":"instruction","level":"%s","code":"%s","message":"%s"' \
    "$level" "$_code" "$escaped_message" >&2

  if [[ -n $_reason ]]
  then
    printf ',"reason":"%s"' "$(aictl__json_escape "$_reason")" >&2
  fi

  if [[ $level == error ]]
  then
    printf ',"retryable":false' >&2
  elif [[ $level == warning ]]
  then
    printf ',"retryable":true' >&2

    # Build structured bypass object (always NIRMI for warnings)
    printf ',"bypass":{"mechanism":"environment_variable","name":"TIMVISHER_AGENT_NIRMI","value":"1"' >&2
    if [[ -n $_command ]]
    then
      printf ',"command":"TIMVISHER_AGENT_NIRMI=1 %s"' "$(aictl__json_escape "$_command")" >&2
    fi
    printf '}' >&2
  fi

  if (( 0 < ${#_suggestions[@]} ))
  then
    printf ',"suggestions":[' >&2
    local first=true s
    for s in "${_suggestions[@]}"
    do
      if [[ $first == true ]]; then first=false; else printf ',' >&2; fi
      printf '"%s"' "$(aictl__json_escape "$s")" >&2
    done
    printf ']' >&2
  fi

  if [[ -n $_doc ]]
  then
    printf ',"doc":"%s"' "$(aictl__json_escape "$_doc")" >&2
  fi

  printf '}\n' >&2
}

# Fatal error — always exits non-zero. Not bypassable.
# Usage: aictl_die [--code C] [--message M] [--reason R] [--doc D] [--suggestion S]...
#    or: aictl_die <code> <message> [suggestion...]
aictl_die() {
  aictl__emit error "$@"
  exit 1
}

# Blocking warning — exits unless TIMVISHER_AGENT_NIRMI=1.
# With NIRMI: prints bypass JSON to stderr, returns 0.
# Without NIRMI: prints warning JSON, exits non-zero.
# Usage: aictl_warn [--code C] [--message M] [--command CMD] [--reason R] [--doc D] [--suggestion S]...
#    or: aictl_warn <code> <message> [suggestion...]
aictl_warn() {
  # Parse just enough to get the code for the bypass message
  local _bypass_code=""
  local arg
  for arg in "$@"
  do
    case "$arg" in
      --code) ;;
      *)
        if [[ $_bypass_code == __next ]]
        then
          _bypass_code=$arg
          break
        elif [[ $arg != --* ]]
        then
          _bypass_code=$arg
          break
        fi
        ;;
    esac
    if [[ $arg == --code ]]; then _bypass_code=__next; fi
  done

  if [[ -n ${TIMVISHER_AGENT_NIRMI:-} ]]
  then
    printf '{"type":"instruction","level":"bypass","code":"%s","message":"Guardrail skipped. Be sure you know what you are doing."}\n' \
      "$_bypass_code" >&2
    return 0
  fi

  aictl__emit warning "$@"
  exit 1
}
