timvisher_date() {
  local date_path
  if date_path=$(type -P date) &&
      [[ ${TIMVISHER_DATE_FLAVOR-} != "$date_path":gnu &&
         ${TIMVISHER_DATE_FLAVOR-} != "$date_path":bsd ]]
  then
    TIMVISHER_DATE_FLAVOR=$(command timvisher_date flavor) &&
      export TIMVISHER_DATE_FLAVOR
  fi
  command timvisher_date "$@"
}

function days_ago {
  local days=$1 epoch
  epoch=$(timvisher_date epoch "$days days ago") || return
  timvisher_date format "$epoch" '+%a %b %e %H:%M:%S %Z %Y'
}

iso8601() {
    # follows POSIX so it's cross platform
    date -u "+%Y-%m-%dT%H:%M:%SZ"
}
