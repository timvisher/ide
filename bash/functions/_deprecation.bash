_ide_deprecated() {
    echo "DEPRECATED. Use $1 instead." >&2
    local command=$1
    shift
    "$command" "$@"
}
