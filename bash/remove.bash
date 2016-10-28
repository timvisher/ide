#!/usr/bin/env bash

if [[ ! -e ~/git/ide/bash/remove.bash ]]
then
    echo '# Please check out to ~/git/ide' >&2
    exit 1
fi

shopt -s extglob

for f in !(install.bash|remove.bash|bin)
do
    if [[ -e ~/.$f ]]
    then
        if [[ $(readlink "$HOME/.$f") == $HOME/git/ide/bash/$f ]]
        then
            rm -v ~/."$f"
        else
            echo "# Skipping ~/.$f. Doesn't point to $HOME/git/ide/bash/$f." >&2
        fi
    else
        echo "# Skipping ~/.$f. Doesn't exist." >&2
    fi
done

if [[ -e ~/bin ]]
then
    if [[ $(readlink ~/bin) == $HOME/git/ide/bash/bin ]]
    then
        rm -v ~/bin
    else
        echo "# Skipping ~/bin. Doesn't point to $HOME/git/ide/bash/bin"
    fi
else
    echo "# Skipping ~/bin. Doesn't exist."
fi
