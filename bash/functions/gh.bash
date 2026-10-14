#!/usr/bin/env bash

# Shared gh helpers for timvisher_gh and timvisher_git. The gh PATH shim
# (bash/bin/gh) selects the gh account for every gh call on its own.

# Echo OWNER/REPO from a git remote URL — https, scp-style (git@host:o/r), and
# ssh:// forms. Host-agnostic, so GitHub Enterprise host aliases (a host other
# than github.com, used to route an alternate SSH key) parse like github.com.
timvisher_gh__repo_spec_from_url() {
  local url=${1%.git}
  case "$url" in
    *://*) url=${url#*://}; url=${url#*/} ;;   # scheme://host/owner/repo
    *:*)   url=${url#*:} ;;                     # user@host:owner/repo
  esac
  printf '%s\n' "$url"
}

# Resolve which of an alias's candidate orgs hosts a repo. Probes each
# candidate ($3, preferred-first comma-separated) through gh, whose shim picks
# each candidate's account; the first HTTP 200 wins. Caches the answer at
# $cache_root/<alias>/<repo>; cache hits never probe. Args: $1 alias, $2 repo,
# $3 candidates, $4 gh binary (default gh). Prints the owner and returns 0 on
# success; returns non-zero with no output when no candidate hosts the repo or
# GitHub can't be reached (caller decides whether that is fatal). No automatic
# invalidation — bust the cache by hand.
timvisher_gh__owner_for_repo() {
  local alias="$1" repo="$2" candidates="$3" gh_bin="${4:-gh}"
  [[ -n $alias && -n $repo && -n $candidates ]] || return 1

  local cache_root="${TIMVISHER_GH_CACHE_DIR:-${HOME}/.cache/timvisher_gh}/repo_owner"
  local cache_file="${cache_root}/${alias}/${repo}"

  if [[ -r $cache_file ]]
  then
    local cached
    cached=$(< "$cache_file")
    cached=${cached//[[:space:]]/}
    if [[ -n $cached ]]
    then
      printf '%s\n' "$cached"
      return 0
    fi
  fi

  local -a candidate_list
  local IFS=,
  read -ra candidate_list <<< "$candidates"
  unset IFS

  local candidate resolved=""
  for candidate in "${candidate_list[@]}"
  do
    [[ -n $candidate ]] || continue
    if "$gh_bin" api "/repos/${candidate}/${repo}" --silent >/dev/null 2>&1
    then
      resolved="$candidate"
      break
    fi
  done

  [[ -n $resolved ]] || return 1

  mkdir -p "${cache_root}/${alias}" 2>/dev/null &&
    printf '%s' "$resolved" > "$cache_file" 2>/dev/null

  printf '%s\n' "$resolved"
  return 0
}
