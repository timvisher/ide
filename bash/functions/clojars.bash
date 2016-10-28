search_clojars() {
    local term="$1"

    curl -s "https://clojars.org/search?q=$term&format=json" \
        | jq -r '.results[] | "[\(.group_name)/\(.jar_name) \"\(.version)\"] # \(.description)"'
}
