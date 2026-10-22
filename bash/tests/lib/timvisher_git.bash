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

# Create a mock gh answering the calls timvisher_gh info makes, plus the
# actions timvisher_git still runs directly (repo set-default, repo fork)
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

not_found() {
  echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
  echo 'gh: Not Found (HTTP 404)' >&2
  exit 1
}

jq_expr=
silent=
for arg in "$@"
do
  [[ $arg == --silent ]] && silent=1
done
args=("$@")
for (( i = 0; i < ${#args[@]}; i += 1 ))
do
  [[ ${args[i]} == --jq ]] && jq_expr=${args[i + 1]}
done

emit() {
  [[ -n $silent ]] && exit 0
  if [[ -n $jq_expr ]]
  then
    jq -r "$jq_expr" <<<"$1"
  else
    printf '%s\n' "$1"
  fi
  exit 0
}

case "$1 $2" in
  'repo set-default'|'repo fork') exit 0 ;;
  'pr list')
    [[ $target_repo == upstream/repo && $4 == merged-branch ]] && echo 9
    exit 0
    ;;
esac

[[ $1 == api ]] || exit 1

if [[ $2 == user && -n $target_repo ]]
then
  emit '{"login":"myuser"}'
fi

path=${2#/}
path=${path#repos/}

case $path in
  */*/branches/*)
    case $path in
      parentorg/parentrepo/branches/main|\
      myuser/parentrepo/branches/main|\
      nopush/parentrepo/branches/main)
        emit '{"name":"main"}' ;;
      *) not_found ;;
    esac
    ;;
  upstream/repo/pulls/1|upstream/repo/pulls/4)
    emit '{"state":"open","merged":false,"head":{"ref":"feature","repo":{"full_name":"fork-owner/repo"}},"base":{"ref":"main"}}' ;;
  upstream/repo/pulls/5)
    emit '{"state":"closed","merged":true,"head":{"ref":"done","repo":{"full_name":"upstream/repo"}},"base":{"ref":"dev"}}' ;;
  upstream/repo/pulls/2)
    emit '{"state":"open","merged":false,"head":{"ref":"feature","repo":null},"base":{"ref":"main"}}' ;;
  upstream/repo/pulls/3)
    emit '{"state":"open","merged":false,"head":{"ref":"feature","repo":{"full_name":null}},"base":{"ref":"main"}}' ;;
  */*/pulls/*) not_found ;;
  oldorg/testrepo)
    emit '{"fork":false,"parent":null,"source":null,"archived":true,"permissions":{"push":false},"topics":[],"default_branch":"main"}' ;;
  liveorg/testrepo)
    emit '{"fork":false,"parent":null,"source":null,"archived":false,"permissions":{"push":false},"topics":[],"default_branch":"main"}' ;;
  parentorg/parentrepo|parentorg/collisionrepo)
    emit '{"fork":false,"parent":null,"permissions":{"push":false},"topics":[],"default_branch":"main"}' ;;
  myuser/parentrepo|altuser/parentrepo)
    emit '{"fork":true,"parent":{"full_name":"parentorg/parentrepo"},"source":{"full_name":"parentorg/parentrepo"},"permissions":{"push":true},"topics":[],"default_branch":"main"}' ;;
  nopush/parentrepo)
    emit '{"fork":true,"parent":{"full_name":"parentorg/parentrepo"},"source":{"full_name":"parentorg/parentrepo"},"permissions":{"push":false},"topics":[],"default_branch":"main"}' ;;
  softforkuser/parentrepo)
    emit '{"fork":true,"parent":{"full_name":"parentorg/parentrepo"},"source":{"full_name":"parentorg/parentrepo"},"permissions":{"push":true},"topics":["soft-fork"],"default_branch":"main"}' ;;
  pushable/ownedrepo)
    emit '{"fork":false,"parent":null,"permissions":{"push":true},"topics":[],"default_branch":"main"}' ;;
  myuser/collisionrepo)
    # Same name as parentorg's repo but NOT a fork of it. The fork
    # command must die loudly here instead of silently cloning this
    # unrelated repo.
    emit '{"fork":false,"parent":null,"permissions":{"push":true},"topics":[],"default_branch":"main"}' ;;
  *)
    # Real gh writes a 4xx error body to STDOUT and exits non-zero; the
    # 404 tests rely on that body not leaking.
    not_found ;;
esac
MOCK
chmod +x "$tmpdir/mockbin/gh"
# timvisher_git reads GitHub through timvisher_gh info, so run the real one
# against the mock gh.
cat > "$tmpdir/mockbin/timvisher_gh" <<MOCK
#!/usr/bin/env bash
exec python3 "${script_dir%/bash}/python/bin/timvisher_gh" "\$@"
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
