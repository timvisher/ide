#!/usr/bin/env bash

# Shared setup for the timvisher_git suites: sourced by
# bash/tests/timvisher_git (units, git mocked) and
# bash/tests/integration/timvisher_git (real repositories). It sources
# the script's functions into the suite and mocks git, gh and
# timvisher_gh.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/timvisher_tests.bash" || exit 1
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/mock_commands.bash" || exit 1


# shellcheck source=/dev/null
source ~/.functions/logging.bash ||
  { echo "Unable to source logging functions" >&2; exit 1; }

failures=0
tests=0

fail() {
  echo "FAIL: $1" >&2
  ((failures++)) || true
}

pass() {
  echo "PASS: $1"
}

run_test() {
  ((tests++)) || true
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" ||
  die "cannot resolve script_dir"
script="${script_dir}/bin/timvisher_git"

# GNU stat first: BSD stat has no -c and fails, while GNU stat -f prints
# file-system information instead of failing.
file_mtime() {
  stat -c '%Y' "$1" 2> /dev/null || /usr/bin/stat -f '%m' "$1"
}

tmpdir=$(mktemp -d) ||
  die "mktemp failed"
trap 'rm -rf "$tmpdir"' EXIT

[[ -n ${TIMVISHER_TESTS_TEMPLATE-} ]] ||
  die "run this suite through timvisher_tests"
ide_config="$XDG_CONFIG_HOME/timvisher/ide"
if [[ -L $ide_config ]]
then
  rm -- "$ide_config" ||
    die "cannot unlink '$ide_config'"
fi
mkdir -p "$ide_config" ||
  die "cannot create '$ide_config'"

# Create a minimal config dir so the script can initialize
config_dir="$tmpdir/config"
mkdir -p "$config_dir/bash/bin/timvisher_git_hooks" ||
  die "cannot create config dir"

# Create minimal cache and live dirs
cache_dir="$tmpdir/cache"
live_dir="$tmpdir/git"
mkdir -p "$cache_dir" "$live_dir" ||
  die "cannot create cache/live dirs"

# Declare the associative array at global scope BEFORE sourcing the script.
# typeset -A inside a function creates a local, so the eval'd script body's
# declaration would be lost when source_timvisher_git returns.
typeset -A org_aliases

# Create mock SELF_DIR with test config files
mock_self_dir="$tmpdir/mock_self_dir"
mkdir -p "$mock_self_dir/timvisher_git.config"
printf '%s\n' "myuser" "altuser" > "$mock_self_dir/timvisher_git.config/github_user_aliases"

# Source the script in a subshell-safe way by overriding env vars
# and intercepting the final case block
source_timvisher_git() {
  export TIMVISHER_GIT_HOME="$live_dir"
  # Disable agent safety guards in ~/bin/git so command git worktree add
  # and similar operations work during tests.
  unset TIMVISHER_AGENT

  # Rename config_dir so script finds our test config
  mkdir -p "$ide_config"
  # Empty org aliases file
  : > "$ide_config/git_org_aliases"

  # Extract function definitions by stripping the final dispatch
  # shellcheck disable=SC2016
  local body source_ref='${BASH_SOURCE[0]}'
  body=$(sed '/^case \$1 in$/,$ d' "$script")
  # Eval'd here, ${BASH_SOURCE[0]} would be this file, and the script finds
  # real_bin.bash and its own bin directory relative to its own path.
  body=${body//"$source_ref"/"$script"}
  eval "$body"
  # Override SELF_DIR after eval so it's not overwritten by the script
  SELF_DIR="$mock_self_dir"
  # Re-load github_user_aliases from the mock config
  github_user_aliases=()
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line ]] && continue
    [[ $line == \#* ]] && continue
    github_user_aliases+=("$line")
  done < "$mock_self_dir/timvisher_git.config/github_user_aliases"
}

# git, gh and timvisher_gh are mocked, and brew --prefix points the
# script's "$(brew --prefix)/bin/git" at the same mock. Each suite
# decides what the mocks answer. timvisher_gh is answered at its CLI;
# only the integration suite's fit cases run the real one.
mock_init ||
  die "mock_init failed"
mock_command gh timvisher_gh ||
  die "mock_command failed"
real_git=$(mock_real git) ||
  die "no real git on the base PATH"
mock_brew_prefix
