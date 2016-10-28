backup() {
  cp "$1" "$1".$(date "+%Y%m%dT%H%M%S").bak
}
