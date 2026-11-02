#!/usr/bin/env bash

# One log for wrapped tool calls, so every call is legible after the fact:
# who ran what, where, when, and how it went (cf-m1w0.28).
#
#   timvisher_tool_log_run <tool> <real-binary> [<arg>...]
#     run <real-binary> (stdin, stdout and the tty pass through), log the
#     call, return its exit status
#   timvisher_tool_log_write <tool> <real> <t0> <rc> <extra> [<arg>...]
#     log a call that already ran: <t0> is its $EPOCHREALTIME, <extra> a
#     JSON fragment of more fields (',"k":v' or empty)
#   timvisher_tool_log_caller
#     print the caller object below, for wrappers that act on it
#   timvisher_tool_log_json <string>
#     print <string> as a JSON string literal, for building <extra>
#   timvisher_tool_log_when_epoch <when>
#     print the epoch seconds for 30m, 2h, 3d or an ISO 8601 UTC time,
#     for the readers' --since and --until
#
# One JSON line per call goes to <log dir>/<tool>.jsonl: ts (UTC), epoch,
# tool, real, argv (secrets redacted), cwd, rc, duration_ms, host, and
# caller, plus <extra>. The caller comes from the environment the agent
# harness exports, so no process walk is needed on hot paths like git:
#   {"kind":"claude","pid":N,"session_id":"...","name":"cfctl-25"}
#     CLAUDE_PID names a live process with ~/.claude/sessions/<pid>.json
#   {"kind":"claude","session_id":"..."}
#     CLAUDE_CODE_SESSION_ID without a readable session file
#   {"kind":"codex","pid":N}
#     TIMVISHER_CODEX (set by the codex wrapper)
#   {"kind":"human","tty":"ttys003"}
#     otherwise
#
# Only the args are logged, never the environment, so a wrapper under
# 'op run' cannot leak resolved secrets.
#
# The log dir is ~/Library/Logs/timvisher/tools on macOS and
# ${XDG_STATE_HOME:-~/.local/state}/timvisher/logs elsewhere;
# TIMVISHER_TOOL_LOG_DIR overrides it. A log write that fails warns on
# stderr and never changes the tool's result. timvisher_tool_log reads
# the logs; timvisher_wrapper_logs_rotate rotates them.

timvisher_tool_log_dir() {
  if [[ -n ${TIMVISHER_TOOL_LOG_DIR-} ]]
  then
    printf '%s\n' "$TIMVISHER_TOOL_LOG_DIR"
  elif [[ $OSTYPE == darwin* ]]
  then
    printf '%s\n' "$HOME/Library/Logs/timvisher/tools"
  else
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/timvisher/logs"
  fi
}

timvisher_tool_log_when_epoch() {
  local when=$1 n
  if [[ $when =~ ^([0-9]+)([smhd])$ ]]
  then
    n=${BASH_REMATCH[1]}
    case ${BASH_REMATCH[2]} in
      s) ;;
      m) (( n *= 60 )) ;;
      h) (( n *= 3600 )) ;;
      d) (( n *= 86400 )) ;;
    esac
    printf '%s\n' "$(( EPOCHSECONDS - n ))"
    return 0
  fi
  jq -nr --arg w "$when" '
    ($w | if test("T") then . else . + "T00:00" end
        | if test("Z$") then . else . + "Z" end
        | if test("T[0-9]{2}:[0-9]{2}Z$") then sub("Z$"; ":00Z") else . end
        | sub("\\.[0-9]+Z$"; "Z")
        | fromdateiso8601)' 2>/dev/null
}

# JSON string literal for $1, in timvisher_tool_log__json_out.
timvisher_tool_log__json() {
  local v=$1
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  v=${v//$'\n'/\\n}
  v=${v//$'\r'/\\r}
  v=${v//$'\t'/\\t}
  timvisher_tool_log__json_out="\"$v\""
}

timvisher_tool_log__secret_flag() {
  case ${1,,} in
    --token|--password|--passwd|--secret|--api-key|--apikey|--client-secret|--auth|--auth-token|--access-token|--with-token|--private-key)
      return 0
      ;;
  esac
  return 1
}

# $1 with secrets replaced, in timvisher_tool_log__redacted.
timvisher_tool_log__redact() {
  local arg=$1 name
  case $arg in
    ghp_*|gho_*|ghu_*|ghs_*|ghr_*|github_pat_*|sk-*|xoxb-*|xoxp-*|glpat-*|eyJ*.*.*|*[Aa]uthorization:*|[Bb]earer\ *)
      timvisher_tool_log__redacted='<redacted>'
      return
      ;;
  esac
  if [[ $arg =~ AKIA[0-9A-Z]{16} ]]
  then
    timvisher_tool_log__redacted='<redacted>'
    return
  fi
  if [[ $arg == *=* ]]
  then
    name=${arg%%=*}
    case ${name,,} in
      *token*|*password*|*passwd*|*secret*|*api_key*|*apikey*|*api-key*|*private_key*|*credential*)
        timvisher_tool_log__redacted="${name}=<redacted>"
        return
        ;;
    esac
  fi
  timvisher_tool_log__redacted=$arg
}

# JSON array of the args, redacted, in timvisher_tool_log__argv_out.
timvisher_tool_log__argv() {
  local out='' sep='' arg redact_next=false
  for arg in "$@"
  do
    if [[ $redact_next == true ]]
    then
      timvisher_tool_log__redacted='<redacted>'
      redact_next=false
    else
      timvisher_tool_log__redact "$arg"
      if timvisher_tool_log__secret_flag "$arg"
      then
        redact_next=true
      elif [[ $arg == --*=* ]] && timvisher_tool_log__secret_flag "${arg%%=*}"
      then
        timvisher_tool_log__redacted="${arg%%=*}=<redacted>"
      fi
    fi
    timvisher_tool_log__json "$timvisher_tool_log__redacted"
    out+="$sep$timvisher_tool_log__json_out"
    sep=,
  done
  timvisher_tool_log__argv_out="[$out]"
}

# JSON object for the caller, in timvisher_tool_log__caller_out.
timvisher_tool_log__caller() {
  local sessions=${TIMVISHER_TOOL_LOG_SESSIONS_DIR:-$HOME/.claude/sessions}
  local file content session_id='' name='' tty pid

  if [[ -n ${CLAUDE_PID-} ]] && kill -0 "$CLAUDE_PID" 2>/dev/null
  then
    file=$sessions/$CLAUDE_PID.json
    if [[ -r $file ]] && content=$(< "$file")
    then
      [[ $content =~ \"sessionId\":\"([^\"]*)\" ]] && session_id=${BASH_REMATCH[1]}
      [[ $content =~ \"name\":\"([^\"]*)\" ]] && name=${BASH_REMATCH[1]}
      timvisher_tool_log__json "$session_id"
      session_id=$timvisher_tool_log__json_out
      timvisher_tool_log__json "$name"
      timvisher_tool_log__caller_out="{\"kind\":\"claude\",\"pid\":${CLAUDE_PID},\"session_id\":${session_id},\"name\":${timvisher_tool_log__json_out}}"
      return
    fi
  fi
  if [[ -n ${CLAUDE_CODE_SESSION_ID-} ]]
  then
    timvisher_tool_log__json "$CLAUDE_CODE_SESSION_ID"
    timvisher_tool_log__caller_out="{\"kind\":\"claude\",\"session_id\":${timvisher_tool_log__json_out}}"
    return
  fi
  if [[ -n ${TIMVISHER_CODEX-} ]]
  then
    pid=${TIMVISHER_AGENT_WRAPPER_EXEC%%:*}
    [[ $pid =~ ^[0-9]+$ ]] || pid=null
    timvisher_tool_log__caller_out="{\"kind\":\"codex\",\"pid\":${pid}}"
    return
  fi

  tty=none
  if [[ -t 0 ]]
  then
    tty=$(tty 2>/dev/null) || tty=none
    tty=${tty#/dev/}
  fi
  timvisher_tool_log__json "$tty"
  timvisher_tool_log__caller_out="{\"kind\":\"human\",\"tty\":${timvisher_tool_log__json_out}}"
}

timvisher_tool_log_caller() {
  timvisher_tool_log__caller
  printf '%s\n' "$timvisher_tool_log__caller_out"
}

timvisher_tool_log_json() {
  timvisher_tool_log__json "$1"
  printf '%s\n' "$timvisher_tool_log__json_out"
}

timvisher_tool_log_write() {
  local tool=$1 real=$2 t0=$3 rc=$4 extra=$5
  shift 5
  local now=$EPOCHREALTIME dir file ts host line
  local a=${t0/[.,]/} b=${now/[.,]/}

  dir=$(timvisher_tool_log_dir)
  file=$dir/$tool.jsonl
  TZ=UTC printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' "${t0%%[.,]*}"
  ts+=".${t0#*[.,]}"
  ts=${ts:0:23}Z
  host=${HOSTNAME:-unknown}

  timvisher_tool_log__argv "$@"
  timvisher_tool_log__caller
  timvisher_tool_log__json "$ts"; line="{\"ts\":$timvisher_tool_log__json_out"
  line+=",\"epoch\":${t0/,/.}"
  timvisher_tool_log__json "$tool"; line+=",\"tool\":$timvisher_tool_log__json_out"
  timvisher_tool_log__json "$real"; line+=",\"real\":$timvisher_tool_log__json_out"
  line+=",\"argv\":$timvisher_tool_log__argv_out"
  timvisher_tool_log__json "$PWD"; line+=",\"cwd\":$timvisher_tool_log__json_out"
  line+=",\"rc\":${rc},\"duration_ms\":$(( (b - a) / 1000 ))"
  timvisher_tool_log__json "${host%%.*}"; line+=",\"host\":$timvisher_tool_log__json_out"
  line+=",\"caller\":$timvisher_tool_log__caller_out${extra}}"

  if ! { [[ -d $dir ]] || mkdir -p -- "$dir"; } 2>/dev/null ||
     ! printf '%s\n' "$line" >> "$file" 2>/dev/null
  then
    printf 'tool_log: could not append to "%s"\n' "$file" >&2
  fi
}

timvisher_tool_log_run() {
  local tool=$1 real=$2
  shift 2
  local t0=$EPOCHREALTIME rc

  # Ctrl-C or a kill still logs the call: the traps only note it, and bash
  # runs them after the child exits.
  trap ':' INT TERM HUP
  "$real" "$@"
  rc=$?
  trap - INT TERM HUP

  timvisher_tool_log_write "$tool" "$real" "$t0" "$rc" '' "$@"
  return "$rc"
}
