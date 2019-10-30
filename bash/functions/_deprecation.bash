_ide_deprecated() {
    echo "DEPRECATED. Use $1 instead." >&2
    local command=$1
    shift
    "$command" "$@"
}

_ide_broken() {
  echo "BROKEN. Fix if you wish" >&2
}
