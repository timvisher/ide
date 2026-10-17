#!/usr/bin/env bash

shopt -s extglob

core=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 1
overlay=
force=

usage() {
    echo "# Usage: install.bash [--core <path>] [--overlay <path>] [--force]" >&2
}

while (( 0 < $# ))
do
    case $1 in
        --core|--overlay)
            if [[ -z ${2-} ]]
            then
                echo "# $1 needs a path" >&2
                usage
                exit 1
            fi
            if [[ $1 == --core ]]
            then
                core=$(cd "$2" && pwd -P) || { echo "# No core at '$2'" >&2; exit 1; }
            else
                overlay=$(cd "$2" && pwd -P) || { echo "# No overlay at '$2'" >&2; exit 1; }
            fi
            shift 2
            ;;
        --force)
            force=1
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

link_root() {
    local link=$1 target=$2

    if [[ -L $link && ! -e $link ]]
    then
        rm -- "$link" || return 1
    fi
    if [[ -e $link ]]
    then
        if [[ $link -ef $target ]]
        then
            return 0
        fi
        echo "# $link exists and isn't $target" >&2
        return 1
    fi
    mkdir -p "$(dirname "$link")" &&
        ln -v -s "$target" "$link"
}

link_root ~/git/ide "$core" || exit 1

if [[ -n $overlay ]]
then
    link_root ~/.config/timvisher/ide "$overlay" || exit 1
fi

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

cd ~/git/ide/bash || exit

for f in !(install.bash|bin)
do
    if [[ -e ~/.$f ]]
    then
        if [[ ! ~/.$f -ef ~/git/ide/bash/$f ]]
        then
            found_error "$HOME/.$f exists and doesn't point to $HOME/git/ide/bash/$f"
        fi
    fi
done

if [[ -e ~/bin ]]
then
    if [[ ! ~/bin -ef ~/git/ide/bash/bin ]]
    then
        found_error "$HOME/bin exists and doesn't point to $HOME/git/ide/bash/bin"
    fi
fi

if [[ -e ~/.config/emacs && ! ~/.config/emacs -ef ~/git/ide/emacs/emacs.d ]]
then
    found_error "$HOME/.config/emacs exists and doesn't point to $HOME/git/ide/emacs/emacs.d"
fi

if (( 0 < ${#errors[@]} ))
then
    echo '# Errors found' >&2
    for message in "${errors[@]}"
    do
        echo "$message" >&2
    done
    if [[ -n $force ]]
    then
        echo "# Forcing install" >&2
    else
        exit 1
    fi
fi

for f in !(install.bash|remove.bash|bin)
do
    if [[ ! ~/.$f -ef ~/git/ide/bash/$f ]]
    then
        ln -v -sf ~/git/ide/bash/"$f" ~/".$f" || { echo "# Couldn't create link for ~/.$f" >&2; exit 1; }
    fi
done

if [[ ! ~/bin -ef ~/git/ide/bash/bin ]]
then
    ln -v -sf ~/git/ide/bash/bin ~/bin || { echo "# Couldn't link ~/bin" >&2; exit 1; }
fi

~/git/ide/git/bin/install || { echo '# git/bin/install failed' >&2; exit 1; }

link_root ~/.config/emacs ~/git/ide/emacs/emacs.d || exit 1

agent_homes=(~/git/ide/ai/HOME)
if [[ -d ~/.config/timvisher/ide/ai/HOME ]]
then
    agent_homes+=(~/.config/timvisher/ide/ai/HOME)
fi
~/git/ide/bash/bin/timvisher_agents_install "${agent_homes[@]}" || exit 1

# Enable Touch ID for sudo now if we're at a terminal on a capable Mac. The
# command self-gates (macOS, sensor, tty, already-configured) and always exits
# 0, so this is a silent no-op when unattended or not applicable. bashrc calls
# it too, so an unattended install still completes on the first attended shell.
~/git/ide/bash/bin/enable-touchid-sudo

echo "All good. Please open a new shell for the changes to take effect."
