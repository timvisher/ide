#!/usr/bin/env bash

# Shared setup for the timvisher_git suites: sourced by
# bash/tests/timvisher_git (units, git mocked) and
# bash/tests/integration/timvisher_git (real repositories). It sources
# the script's functions into the suite and mocks gh and timvisher_gh.

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

# Create mock gh that handles pr view, api /repos/, repo set-default, repo view
mkdir -p "$tmpdir/mockbin" ||
  die "cannot create mockbin dir"
cat > "$tmpdir/mockbin/gh" <<'MOCK'
#!/usr/bin/env bash
target_repo=''
if [[ $1 == -R ]]
then
  target_repo=$2
  shift 2
fi

# --- gh repo set-default: no-op ---
if [[ $1 == repo && $2 == set-default ]]; then
  exit 0
fi

if [[ $1 == api && $2 == repos/* ]]; then
  repo_path=${2#repos/}
  jq_expr=
  while (( $# )); do
    if [[ $1 == --jq ]]; then jq_expr=$2; shift 2; continue; fi
    shift
  done
  case $repo_path in
    oldorg/testrepo)  json='{"fork":false,"source":null,"archived":true}' ;;
    liveorg/testrepo) json='{"fork":false,"source":null,"archived":false}' ;;
    *) echo '{"message":"Not Found","status":"404"}'; exit 1 ;;
  esac
  if [[ -n $jq_expr ]]; then
    echo "$json" | jq -c "$jq_expr"
  else
    echo "$json"
  fi
  exit 0
fi

# --- gh repo view --json ... --jq ... ---
if [[ $1 == repo && $2 == view ]]; then
  shift 2
  repo_arg=$target_repo
  jq_expr=
  for arg in "$@"; do
    case $arg in
      --json*|--jq*) ;;
      -*) ;;
      *) [[ -z $repo_arg ]] && repo_arg=$arg ;;
    esac
  done
  # Extract --jq value
  jq_expr=
  while (( $# )); do
    if [[ $1 == --jq ]]; then jq_expr=$2; shift 2; continue; fi
    if [[ $1 == --jq=* ]]; then jq_expr=${1#--jq=}; shift; continue; fi
    shift
  done
  case $repo_arg in
    parentorg/parentrepo)
      echo '{"defaultBranchRef":{"name":"main"},"isFork":false,"parent":null,"repositoryTopics":[]}' | jq -r "$jq_expr"
      ;;
    myuser/parentrepo)
      echo '{"defaultBranchRef":{"name":"main"},"isFork":true,"parent":{"owner":{"login":"parentorg"},"name":"parentrepo"},"repositoryTopics":[]}' | jq -r "$jq_expr"
      ;;
    altuser/parentrepo)
      echo '{"defaultBranchRef":{"name":"main"},"isFork":true,"parent":{"owner":{"login":"parentorg"},"name":"parentrepo"},"repositoryTopics":[]}' | jq -r "$jq_expr"
      ;;
    softforkuser/parentrepo)
      echo '{"defaultBranchRef":{"name":"main"},"isFork":true,"parent":{"owner":{"login":"parentorg"},"name":"parentrepo"},"repositoryTopics":[{"name":"soft-fork"}]}' | jq -r "$jq_expr"
      ;;
    *)
      echo "not found" >&2; exit 1 ;;
  esac
  exit 0
fi

# --- gh api user (for current_gh_user) ---
if [[ $1 == api && $2 == user && -n $target_repo ]]
then
  jq_expr=
  while (( $# )); do
    if [[ $1 == --jq ]]; then jq_expr=$2; shift 2; continue; fi
    if [[ $1 == --jq=* ]]; then jq_expr=${1#--jq=}; shift; continue; fi
    shift
  done
  json='{"login":"myuser"}'
  if [[ -n $jq_expr ]]; then
    echo "$json" | jq -r "$jq_expr"
  else
    echo "$json"
  fi
  exit 0
fi

# --- gh repo fork (for the fork command) ---
if [[ $1 == repo && $2 == fork ]]; then
  exit 0
fi

# --- gh api /repos/<owner>/<repo>/branches/<branch> ---
# Mock branch existence: known branches return 200, everything else 404.
# Honor --silent (suppress stdout) the way real `gh api` does.
if [[ $1 == api && $2 == /repos/*/branches/* ]]; then
  br_path=${2#/repos/}
  silent=
  for arg in "$@"; do
    [[ $arg == --silent ]] && silent=1
  done
  case $br_path in
    parentorg/parentrepo/branches/main|\
    myuser/parentrepo/branches/main|\
    nopush/parentrepo/branches/main)
      [[ -n $silent ]] || echo '{"name":"main"}'
      exit 0 ;;
    *) [[ -n $silent ]] || echo '{"message":"Branch not found"}' >&2; exit 1 ;;
  esac
fi

# --- gh api /repos/<owner>/<repo> ---
if [[ $1 == api && $2 == /repos/* ]]; then
  repo_path=${2#/repos/}
  jq_expr=
  while (( $# )); do
    if [[ $1 == --jq ]]; then jq_expr=$2; shift 2; continue; fi
    if [[ $1 == --jq=* ]]; then jq_expr=${1#--jq=}; shift; continue; fi
    shift
  done
  case $repo_path in
    parentorg/parentrepo)
      json='{"fork":false,"parent":null,"permissions":{"push":false},"topics":[],"default_branch":"main"}'
      ;;
    myuser/parentrepo)
      json='{"fork":true,"parent":{"full_name":"parentorg/parentrepo"},"permissions":{"push":true},"topics":[],"default_branch":"main"}'
      ;;
    altuser/parentrepo)
      json='{"fork":true,"parent":{"full_name":"parentorg/parentrepo"},"permissions":{"push":true},"topics":[],"default_branch":"main"}'
      ;;
    nopush/parentrepo)
      json='{"fork":true,"parent":{"full_name":"parentorg/parentrepo"},"permissions":{"push":false},"topics":[],"default_branch":"main"}'
      ;;
    softforkuser/parentrepo)
      json='{"fork":true,"parent":{"full_name":"parentorg/parentrepo"},"permissions":{"push":true},"topics":["soft-fork"],"default_branch":"main"}'
      ;;
    pushable/ownedrepo)
      json='{"fork":false,"parent":null,"permissions":{"push":true},"topics":[],"default_branch":"main"}'
      ;;
    parentorg/collisionrepo)
      json='{"fork":false,"parent":null,"permissions":{"push":false},"topics":[],"default_branch":"main"}'
      ;;
    myuser/collisionrepo)
      # Same name as parentorg's repo but NOT a fork of it. The fork
      # command must die loudly here instead of silently cloning this
      # unrelated repo.
      json='{"fork":false,"parent":null,"permissions":{"push":true},"topics":[],"default_branch":"main"}'
      ;;
    *)
      # Match real gh behavior: error body goes to STDOUT (not stderr),
      # then exit non-zero.  This is what real `gh api` does for HTTP 4xx
      # responses.  Catching this correctly is what the probe_fork_parent
      # 404-leak fix relies on.
      echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
      exit 1
      ;;
  esac
  if [[ -n $jq_expr ]]; then
    echo "$json" | jq -r "$jq_expr"
  else
    echo "$json"
  fi
  exit 0
fi

# --- gh pr view (legacy, for pr_head_repo_spec tests) ---
pr_url=
for arg in "$@"; do
  case $arg in
    https://github.com/*)
      pr_url=$arg
      ;;
  esac
done

case $pr_url in
  https://github.com/upstream/repo/pull/1)
    echo "fork-owner/repo"
    ;;
  https://github.com/upstream/repo/pull/2)
    echo "fork-owner/"
    ;;
  https://github.com/upstream/repo/pull/3)
    echo "fork-owner/"
    ;;
  https://github.com/upstream/repo/pull/4)
    echo "fork-owner/repo"
    ;;
  *)
    echo "not found" >&2
    exit 1
    ;;
esac
MOCK
chmod +x "$tmpdir/mockbin/gh"
# The real timvisher_gh is a Python tool with no venv in the test HOME, so
# its 'info .archived' contract (covered by python/tests/test_gh_info.py) is
# faked here from the mock gh's repo table.
cat > "$tmpdir/mockbin/timvisher_gh" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == -R && $3 == info && $4 == .archived ]] || exit 2
case $2 in
  oldorg/testrepo)  echo true ;;
  liveorg/testrepo) echo false ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$tmpdir/mockbin/timvisher_gh"

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
  local body
  body=$(sed '/^case \$1 in$/,$ d' "$script")
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

# mockbin must be first on PATH to shadow the ~/bin/gh wrapper in the
# runner HOME.
export PATH="$tmpdir/mockbin:$PATH"

# git is mocked ahead of mockbin, and brew --prefix points the script's
# "$(brew --prefix)/bin/git" at the same mock. Each suite decides what
# the mock answers.
mock_init ||
  die "mock_init failed"
real_git=$(mock_real git) ||
  die "no real git on the base PATH"
mock_brew_prefix
