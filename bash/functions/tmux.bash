function new_tmux_session {
    local session_name="$1"

    if tmux has-session -t "$session_name" > /dev/null 2>&1
    then
        echo "# Attempted to create new tmux session $session_name when it already exists!" 2>&1
        return 1
    fi

    local base_dir=$2

    local default_command="bash"

    (
        if ! cd "$base_dir"
        then
            echo "# $base_dir does not exist." >&2
            return 1
        fi

        # tmux -vvvv new-session -d -s "$session_name" -n editor "$default_command" # for debugging
        tmux new-session -d -s "$session_name" -n editor "$default_command"
        if [[ Darwin = $(uname) ]]
        then
            tmux send-keys 'emacs' 'C-m'
        else
            tmux send-keys 'TERM=xterm-256color emacs' 'C-m'
        fi
        tmux set-option -g default-command "$default_command"
        tmux new-window -t "$session_name" -n admin
        tmux new-window -t "$session_name" -n services
        tmux new-window -t "$session_name" -n db
        tmux new-window -t "$session_name" -n tests
        tmux select-window -t 1
        tmux select-window -t 0
    )

    tmux attach -t "$session_name"
}

function matching_git_project() {
    local session_name="$1"
    local unnamespaced="${session_name##*/}"

    gps=("$HOME"/!(Library)/{,*,*/*,*/*/*}/.git)

    # FIXME, this and the below should be the same
    for gp in "${gps[@]}"
    do
        project_name="${gp%/.git}"
        project_name="${project_name##*/}"
        if [[ $project_name = "$unnamespaced"* ]]
        then
            return 0
        fi
    done

    return 1
}

function attach_to_git_project() {
    local session_name="$1"
    local ns="${session_name%/*}"
    local unnamespaced="${session_name##*/}"

    gps=("$HOME"/!(Library)/{,*,*/*,*/*/*}/.git)

    # FIXME, this and the above should be the same
    for gp in "${gps[@]}"
    do
        project_directory="${gp%/.git}"
        project_name="${project_directory##*/}"
        if [[ $project_name = "$unnamespaced"* ]]
        then
            new_tmux_session "$ns/$project_name" "$project_directory"
            return 0
        fi
    done

    echo "Couldn't find a matching git project for $session_name ($unnamespaced)" >&2
    return 1

}

function matching_in_current_dir() {
    local session_name="$1"

    shopt -s nullglob

    for match in "$session_name"*
    do
        if [[ -d $match ]]
        then
            echo "$match"
            shopt -u nullglob
            return
        fi
    done
    shopt -u nullglob
    return 1
}

function ntmux {
    local session_name="$1"
    local base_dir="$2"

    if [[ -z $session_name ]]
    then
        echo 'Usage: ntmux [namespace/]session_name [base_dir]'
        return 1
    fi

    # Used properly

    if tmux has-session -t "$session_name" >/dev/null 2>&1
    then
        # Attach to Existing Session
        tmux attach -t "$session_name"
    elif [[ -n $base_dir ]]
    then
        new_tmux_session "$session_name" "$base_dir"
    elif matching_in_current_dir "$session_name" > /dev/null
    then
        # shellcheck disable=SC2155
        local session_and_dir_name="$(matching_in_current_dir "$session_name")"
        new_tmux_session "$session_and_dir_name"  "$session_and_dir_name"
    elif matching_git_project "$session_name"
    then
        # Create a session for a git project
        attach_to_git_project "$session_name"
    else
        echo "Could not find existing session or git project for '$session_name' and you specified no base directory." >&2
        return 1
    fi
}

alias nt=ntmux
