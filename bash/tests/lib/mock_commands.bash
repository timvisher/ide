#!/usr/bin/env bash

# Mock commands for test suites: stubs first on PATH that answer each
# call at once from rules the test sets up, and record every call so
# the test can assert on them. A suite tests its unit, not the tools the
# unit runs, so git, gh, ps, jq and the rest get mocks.
#
#   source "$(dirname "$0")/lib/mock_commands.bash" || exit 1
#   mock_init || exit 1
#   mock_command git gh
#   mock_respond git --stdout main -- rev-parse --abbrev-ref HEAD
#   mock_respond git --exit 1 -- fetch ...
#   mock_respond gh --run 'printf "%s\n" "$2"' -- api ...
#   ... run the unit ...
#   mock_called git fetch origin main || fail 'did not fetch'
#   mock_finish || (( failures += 1 ))
#
# A rule matches a call when each argument matches its pattern as a
# glob ('*' matches any one argument, 'feature/*' a prefix); a final
# '...' matches whatever arguments remain, including none. The newest
# matching rule answers. A call no rule answers goes to the command's
# passthrough if it has one (mock_passthrough), and otherwise is
# unexpected: it exits 127, says so on stderr, and mock_finish reports
# it as a FAIL: line.
#
# State lives in $TIMVISHER_MOCK_DIR, under TMPDIR, which the runner
# removes. The stubs are separate processes, so rules and calls are
# files, and a subshell or a background job of the unit sees the same
# rules and adds to the same record.

_mock_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || return 1
_mock_seq=0
_mock_stub=$(< "$_mock_lib_dir/mock_command") || return 1

# Create the mock dir and put its bin first on PATH. Also links
# $TIMVISHER_MOCK_DIR/prefix/bin to that bin, for units that run
# "$(brew --prefix)/bin/<cmd>": mock brew --prefix to print
# $TIMVISHER_MOCK_DIR/prefix (mock_brew_prefix) and they reach the
# mocks too.
mock_init() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/mock_commands.XXXXXX") || return 1
  mkdir -p "$dir/bin" "$dir/rules" "$dir/passthrough" "$dir/prefix" || return 1
  ln -s ../bin "$dir/prefix/bin" || return 1
  : > "$dir/calls" || return 1
  : > "$dir/unexpected" || return 1
  export TIMVISHER_MOCK_DIR=$dir
  export PATH=$dir/bin:$PATH
}

# Mock each named command. With no rules, every call to it is
# unexpected.
mock_command() {
  local name
  for name in "$@"
  do
    mkdir -p "$TIMVISHER_MOCK_DIR/rules/$name" || return 1
    # A copy, not a link: callers that resolve a command with realpath
    # (the git wrapper finds the next git that way) must still reach
    # the stub by the mocked name. It runs under this suite's bash, not
    # whichever bash a caller's PATH finds first (macOS's /bin/bash is
    # 3.2).
    if [[ ! -e $TIMVISHER_MOCK_DIR/bin/$name ]]
    then
      printf '#!%s\n%s\n' "$BASH" "${_mock_stub#*$'\n'}" > "$TIMVISHER_MOCK_DIR/bin/$name" &&
        chmod +x "$TIMVISHER_MOCK_DIR/bin/$name" ||
        return 1
    fi
  done
}

# Calls to <name> that no rule answers run <path> with the same
# arguments, still recorded. Use the real tool's path (mock_real) for
# an integration test, or a script of your own for answers no rule can
# give. An empty <path> removes the passthrough.
mock_passthrough() {
  local name=$1 path=${2-}
  mock_command "$name" || return 1
  printf '%s\n' "$path" > "$TIMVISHER_MOCK_DIR/passthrough/$name"
}

# mock_respond <name> [<option>...] [--] <pattern>...
#
#   --stdout <text>  print <text> and a newline on stdout
#   --stderr <text>  print <text> and a newline on stderr
#   --exit <n>       exit <n> (default 0)
#   --times <n>      answer only the first <n> matching calls
#   --run <code>     instead of the above, run <code> as bash with the
#                    call's arguments as "$@"; its status is the call's
#
# With no patterns the rule matches only a call with no arguments; use
# '...' to match any call.
mock_respond() {
  local name=$1
  shift
  local rule_stdout='' rule_stderr='' rule_exit=0 rule_times='' rule_run=''
  local -a rule_patterns=()
  while (( 0 < $# ))
  do
    case $1 in
      --stdout|--stderr|--exit|--times|--run)
        if (( $# < 2 ))
        then
          printf 'mock_respond: %s needs a value\n' "$1" >&2
          return 1
        fi
        ;;
    esac
    case $1 in
      --stdout) rule_stdout=$2; shift 2 ;;
      --stderr) rule_stderr=$2; shift 2 ;;
      --exit) rule_exit=$2; shift 2 ;;
      --times) rule_times=$2; shift 2 ;;
      --run) rule_run=$2; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  rule_patterns=("$@")
  mock_command "$name" || return 1
  # Named so the stub's glob lists them oldest first.
  local rule
  (( _mock_seq += 1 ))
  printf -v rule '%s/rules/%s/%s.%06d.%s.rule' "$TIMVISHER_MOCK_DIR" "$name" \
    "${EPOCHREALTIME/[.,]/}" "$_mock_seq" "${BASHPID:-$$}"
  if [[ -n $rule_run ]]
  then
    printf '%s\n' "$rule_run" > "$rule.run" || return 1
    rule_run=1
  fi
  declare -p rule_patterns rule_stdout rule_stderr rule_exit rule_times rule_run > "$rule"
}

# Forget the rules (all commands, or the named ones) and the record of
# calls, so the next test starts clean. The stubs and passthroughs stay,
# and so do unexpected calls, until mock_finish reports them.
mock_reset() {
  local name
  if (( 0 == $# ))
  then
    rm -rf -- "$TIMVISHER_MOCK_DIR/rules"/*/*.rule*
  else
    for name in "$@"
    do
      rm -rf -- "$TIMVISHER_MOCK_DIR/rules/$name"/*.rule*
    done
  fi
  : > "$TIMVISHER_MOCK_DIR/calls"
}

# Print the recorded calls, all or those to <name>, one per line as
# '<name> <arg>...' with each word quoted for bash (printf %q).
mock_calls() {
  local name=${1-} prefix line
  if [[ -z $name ]]
  then
    cat -- "$TIMVISHER_MOCK_DIR/calls"
    return
  fi
  printf -v prefix '%q' "$name"
  while IFS= read -r line
  do
    if [[ $line == "$prefix" || $line == "$prefix "* ]]
    then
      printf '%s\n' "$line"
    fi
  done < "$TIMVISHER_MOCK_DIR/calls"
}

# Print how many recorded calls to <name> match the patterns (all calls
# to <name> when there are none).
mock_call_count() {
  local name=$1
  shift
  local -a patterns=("$@") words
  local line count=0
  if (( 0 == ${#patterns[@]} ))
  then
    patterns=(...)
  fi
  while IFS= read -r line
  do
    eval "words=($line)"
    _mock_lib_matches patterns "${words[@]:1}" && (( count += 1 ))
  done < <(mock_calls "$name")
  printf '%s\n' "$count"
}

# Succeed when some recorded call to <name> matches the patterns.
mock_called() {
  local count
  count=$(mock_call_count "$@") || return 1
  (( 0 < count ))
}

# Print the calls no rule or passthrough answered; succeed if there
# were any.
mock_unexpected() {
  [[ -s $TIMVISHER_MOCK_DIR/unexpected ]] || return 1
  cat -- "$TIMVISHER_MOCK_DIR/unexpected"
}

# Report each unexpected call as a FAIL: line on stderr, the way suites
# report failures, forget them, and fail if there were any. Run it at
# the end of a suite, or after a test that must not reach past its
# rules.
mock_finish() {
  local line unexpected=0
  while IFS= read -r line
  do
    printf 'FAIL: mock: unexpected call: %s\n' "$line" >&2
    unexpected=1
  done < "$TIMVISHER_MOCK_DIR/unexpected"
  : > "$TIMVISHER_MOCK_DIR/unexpected"
  (( 0 == unexpected ))
}

# Print the path of the real <name>, looked up on the runner's base
# PATH, which holds neither the mocks nor the IDE's wrappers.
mock_real() {
  local name=$1
  [[ -n ${TIMVISHER_TESTS_BASE_PATH-} ]] || {
    printf 'mock_real: TIMVISHER_TESTS_BASE_PATH is unset; run the suite through timvisher_tests\n' >&2
    return 1
  }
  PATH=$TIMVISHER_TESTS_BASE_PATH type -P "$name"
}

# Make brew --prefix print $TIMVISHER_MOCK_DIR/prefix, whose bin is the
# mocks' bin.
mock_brew_prefix() {
  mock_respond brew --stdout "$TIMVISHER_MOCK_DIR/prefix" -- --prefix
}

# The stub's matcher, for the assertions.
_mock_lib_matches() {
  local -n _mock_lib_patterns=$1
  shift
  local -a args=("$@")
  local i
  for i in "${!_mock_lib_patterns[@]}"
  do
    if [[ ${_mock_lib_patterns[i]} == ... ]] && (( i == ${#_mock_lib_patterns[@]} - 1 ))
    then
      return 0
    fi
    (( i < ${#args[@]} )) || return 1
    # shellcheck disable=SC2053
    [[ ${args[i]} == ${_mock_lib_patterns[i]} ]] || return 1
  done
  (( ${#_mock_lib_patterns[@]} == ${#args[@]} ))
}
