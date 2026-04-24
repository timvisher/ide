#!/usr/bin/env bash

# aictl - Structured agent CLI messaging
#
# Functions for agent-aware guardrails following the principles from
# "Most CLIs are built for humans. Agents need more than that."
#
# Provides:
#   aictl_die  - Fatal error, always exits non-zero (not bypassable)
#   aictl_warn - Blocking warning, exits unless NIRMI + REASON both set
#
# Output is JSON to stderr:
#   {"type":"instruction","level":"error|warning|bypass","code":"...","message":"...", ...}
#
# The warning emission deliberately omits any ready-to-paste bypass
# command or mechanism detail. Agents that need to bypass must read the
# doc reference (--doc) and assemble the env vars themselves. Data from
# 2026-04-17..2026-04-21 showed 48 bypasses across 6 sessions; a big
# chunk came from the agent copying the `command` field we used to emit.
#
# Both functions accept --flag arguments for rich fields:
#   --code, --message, --reason, --doc, --suggestion, --command
#
# Positional fallback: <code> <message> [suggestion...]
#
# Environment:
#   TIMVISHER_AGENT_NIRMI=1                 Required to bypass aictl_warn
#   TIMVISHER_AGENT_NIRMI_REASON=<text>     Required; free-form explanation
#                                           — NIRMI alone is no longer sufficient
#
# Every bypass is logged (ts, code, reason, cwd, command) to
#   ${XDG_STATE_HOME:-$HOME/.local/state}/timvisher/wrappers/aictl-bypass/log.jsonl

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
    # Intentionally no "bypass" object. If bypass is legitimately needed,
    # the agent must follow --doc to learn the mechanism.
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

# Non-terminating error — emits the same error JSON as aictl_die but
# returns 1 instead of exiting.  Use this from shell FUNCTIONS (sourced
# into the caller's shell) where `exit` would kill the enclosing
# interactive shell.  Scripts should prefer aictl_die.
#
# Callers should propagate the non-zero return, e.g.:
#   aictl_error --code ... --message ...
#   return 1
# Usage: aictl_error [--code C] [--message M] [--reason R] [--doc D] [--suggestion S]...
#    or: aictl_error <code> <message> [suggestion...]
aictl_error() {
  aictl__emit error "$@"
  return 1
}

# Blocking warning — exits unless BOTH TIMVISHER_AGENT_NIRMI=1 and
# TIMVISHER_AGENT_NIRMI_REASON=<non-empty> are set.
#
# With both: logs a JSONL bypass event, prints bypass JSON to stderr, returns 0.
# With NIRMI only: emits an error explaining REASON is required; exits 1.
# Without either: prints warning JSON, exits 1.
#
# Usage: aictl_warn [--code C] [--message M] [--command CMD] [--reason R] [--doc D] [--suggestion S]...
#    or: aictl_warn <code> <message> [suggestion...]
aictl_warn() {
  # Full parse — we need --code AND --command for the bypass log entry.
  aictl__parse_args "$@"

  if [[ -n ${TIMVISHER_AGENT_NIRMI:-} ]]
  then
    if [[ -z ${TIMVISHER_AGENT_NIRMI_REASON:-} ]]
    then
      # NIRMI alone is no longer sufficient. Fail distinctly so the agent
      # has to supply a reason (which we log) to proceed.
      aictl__emit error \
        --code "aictl_bypass_missing_reason" \
        --message "TIMVISHER_AGENT_NIRMI=1 was set but TIMVISHER_AGENT_NIRMI_REASON is empty. Bypassing a guardrail now requires an explicit reason, which is logged for audit." \
        --reason "NIRMI-only bypasses were being used reflexively. Requiring a reason surfaces intent and creates an audit trail." \
        --suggestion "Set TIMVISHER_AGENT_NIRMI_REASON='<why this specific bypass is necessary>' and retry" \
        --suggestion "Or reconsider — the guard exists for a reason; try the suggested alternative instead"
      exit 1
    fi

    # Log the bypass event (ts, code, reason, cwd, command attempted).
    local _aictl__log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/timvisher/wrappers/aictl-bypass"
    local _aictl__log_file="${_aictl__log_dir}/log.jsonl"
    mkdir -p "$_aictl__log_dir" 2>/dev/null || true
    # Capture timestamp up front; if date fails or returns non-digits,
    # emit JSON null rather than a silent 0 that would corrupt the audit.
    local _aictl__ts
    _aictl__ts=$(date +%s 2>/dev/null || true)
    [[ $_aictl__ts =~ ^[0-9]+$ ]] || _aictl__ts="null"
    {
      printf '{"ts":%s,"code":"%s"' "$_aictl__ts" "$(aictl__json_escape "${_code:-}")"
      printf ',"reason":"%s"' "$(aictl__json_escape "${TIMVISHER_AGENT_NIRMI_REASON}")"
      printf ',"cwd":"%s"' "$(aictl__json_escape "$PWD")"
      if [[ -n ${_command:-} ]]
      then
        printf ',"command":"%s"' "$(aictl__json_escape "$_command")"
      fi
      printf '}\n'
    } >> "$_aictl__log_file" 2>/dev/null || true

    printf '{"type":"instruction","level":"bypass","code":"%s","message":"Guardrail bypassed with logged reason. Be sure you know what you are doing."}\n' \
      "$(aictl__json_escape "${_code:-}")" >&2
    return 0
  fi

  aictl__emit warning "$@"
  exit 1
}
