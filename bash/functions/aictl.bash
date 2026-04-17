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
# Output is JSON to stderr with stable error codes, recovery
# suggestions, retryable flag, and bypass instructions.
#
# Environment:
#   TIMVISHER_AGENT_NIRMI=1  Bypass aictl_warn guards (prints notice, continues)

_aictl_loaded=true

aictl__json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

aictl__emit() {
  local type=$1 code=$2 message=$3
  shift 3

  local escaped_message
  escaped_message=$(aictl__json_escape "$message")

  printf '{"type":"%s","code":"%s","message":"%s"' "$type" "$code" "$escaped_message" >&2

  if [[ $type == error ]]
  then
    printf ',"retryable":false' >&2
  elif [[ $type == warning ]]
  then
    printf ',"retryable":true,"bypass":"TIMVISHER_AGENT_NIRMI=1"' >&2
  fi

  if (( 0 < $# ))
  then
    printf ',"suggestions":[' >&2
    local first=true s escaped_s
    for s in "$@"
    do
      escaped_s=$(aictl__json_escape "$s")
      if [[ $first == true ]]
      then
        printf '"%s"' "$escaped_s" >&2
        first=false
      else
        printf ',"%s"' "$escaped_s" >&2
      fi
    done
    printf ']' >&2
  fi

  printf '}\n' >&2
}

# Fatal error — always exits non-zero. Not bypassable.
# Usage: aictl_die <code> <message> [suggestion...]
aictl_die() {
  local code=$1 message=$2
  shift 2
  aictl__emit error "$code" "$message" "$@"
  exit 1
}

# Blocking warning — exits unless TIMVISHER_AGENT_NIRMI=1.
# With NIRMI: prints bypass JSON to stderr, returns 0.
# Without NIRMI: prints warning JSON with suggestions, exits non-zero.
# Usage: aictl_warn <code> <message> [suggestion...]
aictl_warn() {
  local code=$1 message=$2
  shift 2

  if [[ -n ${TIMVISHER_AGENT_NIRMI:-} ]]
  then
    printf '{"type":"bypass","code":"%s","message":"Guardrail skipped. Be sure you know what you are doing."}\n' "$code" >&2
    return 0
  fi

  aictl__emit warning "$code" "$message" "$@"
  exit 1
}
