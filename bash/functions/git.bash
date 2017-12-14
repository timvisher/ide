#!/usr/bin/env bash

pair_show() {
    git config --global user.name
    git config --global user.email
}

pair_set() {
    if (( 2 != $# )) || [[ $1 != *' and '* ]] || [[ $2 != *+*@stitchdata.com ]]
    then
        echo "# pair_set 'First Lass and First Lass' 'first+first@stitchdata.com'" >&2
        return 1
    fi

    git config --global user.name "$1"
    git config --global user.email "$2"

    pair_show
}

pair_unpair() {
    if (( 2 != $# )) || [[ $1 == *' and '* ]] || ! [[ $2 =~ ^[^+]+@stitchdata.com ]]
    then
        echo "# unpair 'First Last' 'first@stitchdata.com'" >&2
    fi

    git config --global user.name "$1"
    git config --global user.email "$2"

    pair_show
}

# hub is awesome! https://github.com/github/hub
if command -v hub >/dev/null 2>&1
then
    eval "$(hub alias -s)"
fi
