#!/usr/bin/env bash

# Steps are read from the repository's own CI definition rather than
# listed here, so a change upstream makes to its pipeline is picked up
# instead of silently drifting away from what this hook checks.

root=$(git rev-parse --show-toplevel) ||
  {
    printf 'run-tests: not inside a git worktree\n' >&2
    exit 1
  }

cd "$root" ||
  {
    printf 'run-tests: cannot cd to %s\n' "$root" >&2
    exit 1
  }

# The agent SDK shells out to a real Claude Code whenever it can find
# one, which would make the suite depend on whichever version happens to
# be installed. Point it at a binary that always fails so the tests use
# their own mocks.
export CLAUDE_CODE_EXECUTABLE=/usr/bin/false

# ANTHROPIC_MODEL is the first thing resolveModelPreference consults, so a
# shell that has one -- every agent shell does -- resolves a model before
# the allowlist is reached, and the tests that assert on that call fail.
# CI has no such variable; unset it so a run means the same thing whoever
# starts it.
unset ANTHROPIC_MODEL

ci_yaml=.github/workflows/ci.yml

if [[ ! -f $ci_yaml ]]
then
  printf 'run-tests: %s is missing\n' "$ci_yaml" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1
then
  printf 'run-tests: yq is required (brew install yq)\n' >&2
  exit 1
fi

# Read the steps as JSON, not as two line-indexed lists: a step's `run`
# can be a block scalar spanning several lines, which would pair the
# wrong name with the wrong command.
steps=$(yq -o=json '[.jobs.build.steps[] | select(.run) | {"name": .name, "run": .run}]' "$ci_yaml") ||
  {
    printf 'run-tests: cannot read steps from %s\n' "$ci_yaml" >&2
    exit 1
  }

count=$(jq 'length' <<<"$steps") ||
  {
    printf 'run-tests: cannot count steps\n' >&2
    exit 1
  }

if (( count == 0 ))
then
  printf 'run-tests: %s defines no run steps under jobs.build\n' "$ci_yaml" >&2
  exit 1
fi

for (( i = 0; i < count; i += 1 ))
do
  name=$(jq -r --argjson i "$i" '.[$i].name // "step \($i)"' <<<"$steps")
  cmd=$(jq -r --argjson i "$i" '.[$i].run' <<<"$steps")

  printf '=== %s ===\n' "$name"

  # CI always installs from scratch. Locally that costs minutes and is
  # usually a no-op, so only reinstall once node_modules has drifted --
  # which still catches the stale-dependency failures a plain skip hides.
  if [[ $cmd == 'npm ci' ]] && npm ls --all >/dev/null 2>&1
  then
    printf '(node_modules in sync, skipping)\n\n'
    continue
  fi

  if [[ $cmd == 'npm run format:check' ]]
  then
    # CI runs on a clean checkout; here the untracked x.* scratch files
    # would fail prettier, so check only what git tracks.
    files=()
    while IFS= read -r -d '' file
    do
      # Named explicitly, a symlink is an error to prettier; reached by
      # walking a directory, as CI does, it is simply skipped.
      if [[ -L $file ]]
      then
        continue
      fi
      files+=("$file")
    done < <(git ls-files -z '*.ts' '*.tsx' '*.js' '*.jsx' '*.json' '*.md' '*.yml' '*.yaml' '*.css' '*.html')

    if (( ${#files[@]} == 0 ))
    then
      printf '(no tracked files to check)\n'
      rc=0
    else
      npx prettier --check "${files[@]}"
      rc=$?
    fi
  else
    eval "$cmd"
    rc=$?
  fi

  if (( rc != 0 ))
  then
    printf 'run-tests: step failed: %s\n' "$name" >&2
    exit 1
  fi

  printf '\n'
done

printf '=== all CI steps passed ===\n'
