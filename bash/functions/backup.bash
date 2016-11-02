backup() {
  cp -v "$1" "$1"."$(iso8601)".bak
}
