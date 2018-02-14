function days_ago {
  local days=$1
  # shellcheck disable=SC2155
  local current_seconds="$(date +%s)"
  date -r "$(echo "$current_seconds - ($days * 24 * 60 * 60)" | bc)"
}

iso8601() {
    # follows POSIX so it's cross platform
    date -u "+%Y-%m-%dT%H:%M:%SZ"
}
