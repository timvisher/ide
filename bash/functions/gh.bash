#!/usr/bin/env bash

# Shared gh helpers for timvisher_gh and timvisher_git on multi-account
# setups — a personal account and an enterprise-managed (EMU) account on the
# same github.com host, where each can only see its own orgs. The gh PATH shim
# (bash/bin/gh) selects the account for every gh call on its own.
#
# Config-driven and host-agnostic. Employer/org specifics live in config
# (orgs/<owner>/account), never here.

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

# Echo the gh account configured for an org owner, or return 1.
# Config: <config_dir>/orgs/<owner>/account (one gh username).
timvisher_gh__account_for_owner() {
  local owner="$1"
  [[ -n $owner ]] || return 1
  local config_dir="${TIMVISHER_GH_CONFIG_DIR:-${HOME}/.config/timvisher/ide/bash/bin/timvisher_gh.config}"
  local f="${config_dir}/orgs/${owner}/account"
  [[ -r $f ]] || return 1
  local account
  account=$(< "$f")
  account=${account//[[:space:]]/}
  [[ -n $account ]] || return 1
  printf '%s\n' "$account"
}

# Export GH_TOKEN for the account mapped to $1 (owner), using the real gh
# binary $2 to mint the token (so this never recurses through a shim). No-op
# success when there's no mapping, so callers may invoke unconditionally.
# Returns non-zero only when a mapping exists but the token can't be obtained;
# callers decide whether that's fatal (timvisher_gh) or ignorable (the shim).
timvisher_gh__pin_token_for_owner() {
  local owner="$1" real_gh="${2:-gh}"
  local account
  account=$(timvisher_gh__account_for_owner "$owner") || return 0
  local token
  token=$("$real_gh" auth token --hostname github.com --user "$account" 2>/dev/null) || return 1
  [[ -n $token ]] || return 1
  export GH_TOKEN="$token"
  return 0
}

# Resolve which of an alias's candidate orgs hosts a repo. Probes each candidate
# ($3, preferred-first comma-separated) with its own pinned account; the first
# HTTP 200 wins. Caches the answer at $cache_root/<alias>/<repo>; cache hits
# never probe. Args: $1 alias, $2 repo, $3 candidates, $4 gh binary (default gh).
# Prints the owner and returns 0 on success; returns non-zero with no output
# when no candidate hosts the repo or GitHub can't be reached (caller decides
# whether that is fatal). No automatic invalidation — bust the cache by hand.
timvisher_gh__owner_for_repo() {
  local alias="$1" repo="$2" candidates="$3" real_gh="${4:-gh}"
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
    if (
      timvisher_gh__pin_token_for_owner "$candidate" "$real_gh" || exit 1
      "$real_gh" api "/repos/${candidate}/${repo}" --silent >/dev/null 2>&1
    )
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
