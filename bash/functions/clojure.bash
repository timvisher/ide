_rebl_translate_lein_dep() {
    local lein_dep lein_dep_name lein_dep_version

    lein_dep=$1

    IFS=' ' read -r lein_dep_name lein_dep_version <<<"$lein_dep"

    lein_dep_name="${lein_dep_name/[/}"
    lein_dep_version="${lein_dep_version/]/}"

    echo "${lein_dep_name} {:mvn/version ${lein_dep_version}}"
}

_rebl_assert_preconditions() {
    if ! [[ $(type -t clojure) == file ]]
    then
        # I like backticks as a string convention
        # shellcheck disable=SC2016
        echo '`clojure` not installed.' \
             'https://clojure.org/guides/getting_started' >&2
        return 1
    fi
}

rebl() {
    _rebl_assert_preconditions || return 1
    local -a deps
    while [[ -n $1 ]]
    do
        read -r line < <(_rebl_translate_lein_dep "$1")
        shift
        deps+=("$line")
    done
    clojure -Sdeps '{:deps {com.bhauman/rebel-readline {:mvn/version "0.1.4"} '"${deps[*]}"'}}' \
            -M \
            -m rebel-readline.main
}
