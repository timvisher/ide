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
# Messages include stable error codes, recovery suggestions, and
# bypass instructions. All output goes to stderr.
#
# Environment:
#   TIMVISHER_AGENT_NIRMI=1  Bypass aictl_warn guards (prints notice, continues)

_aictl_loaded=true

aictl__emit() {
  local type=$1 code=$2 message=$3
  shift 3

  printf '\n[aictl:%s:%s]\n' "$type" "$code" >&2
  printf '%s\n' "$message" >&2

  if (( 0 < $# ))
  then
    printf '\nSuggestions:\n' >&2
    local s
    for s in "$@"
    do
      printf '  → %s\n' "$s" >&2
    done
  fi

  if [[ $type == warning ]]
  then
    printf '\nBypass: re-run with TIMVISHER_AGENT_NIRMI=1 to skip this guard\n' >&2
  fi
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
# With NIRMI: prints bypass notice to stderr, returns 0.
# Without NIRMI: prints warning with suggestions, exits non-zero.
# Usage: aictl_warn <code> <message> [suggestion...]
aictl_warn() {
  local code=$1 message=$2
  shift 2

  if [[ -n ${TIMVISHER_AGENT_NIRMI:-} ]]
  then
    printf '[aictl:bypass:%s] GUARDRAIL SKIPPED — be sure you know what you are doing.\n' "$code" >&2
    return 0
  fi

  aictl__emit warning "$code" "$message" "$@"
  exit 1
}
