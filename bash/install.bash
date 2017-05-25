#!/usr/bin/env bash

shopt -s extglob

# Check if we're safe to install

if [[ ! -e ~/git/ide/bash/install.bash ]]
then
    echo 'Please check ide out to ~/git/ide' >&2
    exit 1
fi

errors=()

found_error() {
    errors=("${errors[@]}" "# $1")
}

cd ~/git/ide/bash

for f in !(install.bash|bin)
do
    if [[ -e ~/.$f ]]
    then
        if [[ $(readlink ~/".$f") != $HOME/git/ide/bash/$f ]]
        then
            found_error "~/.$f exists and doesn't point to $HOME/git/ide/bash/$f"
        fi
    fi
done

if [[ -e ~/bin ]]
then
    if [[ $(readlink ~/bin) != $HOME/git/ide/bash/bin ]]
    then
        found_error "~/bin exists and doesn't point to $HOME/git/ide/bash/$f"
    fi
fi

if [[ -n "${errors[@]}" ]]
then
    echo '# Errors found' >&2
    for message in "${errors[@]}"
    do
        echo "$message" >&2
    done
    if [[ --force == $1 ]]
    then
        echo "# Forcing install" >&2
    else
        exit 1
    fi
fi

# No errors found.

for f in !(install.bash|remove.bash|bin)
do
    if [[ $(readlink ~/".$f") != $HOME/git/ide/bash/"$f" ]]
    then
        ln -v -sf ~/git/ide/bash/"$f" ~/".$f" || { echo "# Couldn't create link for ~/.$f" >&2; exit 1; }
    fi
done

if [[ $(readlink ~/bin) != $HOME/git/ide/bash/bin ]]
then
    ln -v -sf ~/git/ide/bash/bin ~/bin || { echo "# Couldn't link ~/bin"; exit 1; }
fi

echo "All good. Please open a new shell for the changes to take effect."
