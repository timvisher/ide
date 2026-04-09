shopt -s extglob

function maybe_set_beads_topic {
    local repo_root="$1"
    local topic_file

    if [[ -s "$repo_root/.timvisher_bd_topics/topic.txt" ]]
    then
        topic_file="$repo_root/.timvisher_bd_topics/topic.txt"
    elif [[ -s "$repo_root/.timvisher_EXP_bd_topics/topic.txt" ]]
    then
        topic_file="$repo_root/.timvisher_EXP_bd_topics/topic.txt"
    else
        return 0
    fi

    if ! command -v timvisher_bd_topics >/dev/null 2>&1
    then
        warn "timvisher_bd_topics not found; skipping beads topic set"
        return 0
    fi

    if ! (cd "$repo_root" && command timvisher_bd_topics set)
    then
        warn "timvisher_bd_topics set failed; continuing without beads topic redirect"
        return 0
    fi
}

function new_tmux_session {
    local session_name="${1//./_}"

    if tmux has-session -t="$session_name" > /dev/null 2>&1
    then
        echo "# Attempted to create new tmux session $session_name when it already exists!" 2>&1
        return 1
    fi

    local base_dir=$2

    local target_file="$3"

    local detached="$4"

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
            tmux send-keys -t="$session_name":editor 'emacs'
            if [[ -n $target_file ]]
            then
                tmux send-keys -t="$session_name":editor " '${target_file}'"
            fi
            tmux send-keys -t="$session_name":editor 'C-m'
        else
            echo 'Do you really still mean to be executing outside of Darwin?' >&2
            return 1
            # tmux send-keys 'TERM=xterm-256color emacs' 'C-m'
        fi
        tmux set-option -g default-command "$default_command"
        tmux new-window -t="$session_name" -n admin
        tmux new-window -t="$session_name" -n services
        tmux new-window -t="$session_name" -n db
        tmux new-window -t="$session_name" -n tests
        tmux select-window -t "$session_name":1
        tmux select-window -t "$session_name":0
    )

    if [[ -z $detached ]]
    then
        tmux attach -t="$session_name"
    else
        printf '%s\n' "$session_name"
        info 'attach with: ntmux %q' "$session_name"
    fi
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
    local detached="$2"
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
            new_tmux_session "$ns/$project_name" "$project_directory" "" "$detached"
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
    local detached=
    if [[ $1 == -d ]]
    then
        detached=true
        shift
    fi

    local session_name="${1//./_}"
    local base_dir="$2"
    local target_file

    if [[ -f "$base_dir" ]]
    then
        target_file="$base_dir"
        base_dir="${base_dir%/*}"
    fi

    if [[ -z $session_name ]]
    then
        echo 'Usage: ntmux [-d] [namespace/]session_name [base_dir | file]'
        return 1
    fi

    # Used properly

    if tmux has-session -t="$session_name" >/dev/null 2>&1
    then
        if [[ -z $detached ]]
        then
            # Attach to Existing Session
            tmux attach -t="$session_name"
        else
            printf '%s\n' "$session_name"
            info 'attach with: ntmux '\''%s'\''' "$session_name"
        fi
    elif [[ -n $base_dir ]]
    then
        new_tmux_session "$session_name" "$base_dir" "$target_file" "$detached"
    elif matching_in_current_dir "$session_name" > /dev/null
    then
        # shellcheck disable=SC2155
        local session_and_dir_name="$(matching_in_current_dir "$session_name")"
        new_tmux_session "$session_and_dir_name"  "$session_and_dir_name" "" "$detached"
    elif matching_git_project "$session_name"
    then
        # Create a session for a git project
        attach_to_git_project "$session_name" "$detached"
    else
        echo "Could not find existing session or git project for '$session_name' and you specified no base directory." >&2
        return 1
    fi
}

alias nt=ntmux

function ntmux3__usage() {
    echo 'Usage: ntmux3 [-d] [GitHub PR URL | [github_org_or_org_alias/[repo_name/]]session_name] [base_dir | file]' >&2
    return 1
}

function ntmux3__fail() {
    echo "$1" >&2
    return 1
}

function ntmux3__session_name_from_path() {
    local raw_path="$1"

    [[ -n $raw_path ]] || return 1

    local path="$raw_path"
    if [[ $path == '~' ]]
    then
        path="$HOME"
    elif [[ $path == '~/'* ]]
    then
        path="${HOME}/${path#'~'/}"
    fi

    local candidate_path="$path"

    # Handle file paths by using the parent directory
    if [[ -f $candidate_path && ! -d $candidate_path ]]
    then
        candidate_path="${candidate_path%/*}"
    fi

    if [[ ! -d $candidate_path ]]
    then
        return 1
    fi

    local resolved
    resolved=$(cd "$candidate_path" 2>/dev/null && pwd -P) || return 1

    local home_real
    home_real=$(cd "$HOME" && pwd -P) || return 1

    # Try ~/git/ prefix first (existing worktree path)
    local relative="${resolved#${home_real}/git/}"
    if [[ $relative != "$resolved" && -n $relative ]]
    then
        printf '%s' "$relative"
        return 0
    fi

    # Try path aliases from config
    local config_dir=${XDG_CONFIG_HOME:-${HOME}/.config}/timvisher/ide
    local aliases_file=${config_dir}/ntmux3_path_aliases
    if [[ -r $aliases_file ]]
    then
        local line key value expanded_key
        while IFS= read -r line || [[ -n $line ]]
        do
            [[ -z $line ]] && continue
            [[ $line == \#* ]] && continue
            key=${line%%=*}
            value=${line#*=}
            # Expand tilde in key
            case $key in
                '~')   expanded_key="$home_real" ;;
                '~/'*) expanded_key="${home_real}/${key#'~'/}" ;;
                *)     expanded_key="$key" ;;
            esac
            # Resolve the alias path
            if [[ -d $expanded_key ]]
            then
                expanded_key=$(cd "$expanded_key" && pwd -P) || continue
            fi
            if [[ $resolved == "$expanded_key"/* ]]
            then
                local suffix="${resolved#${expanded_key}/}"
                printf '%s/%s' "$value" "$suffix"
                return 0
            elif [[ $resolved == "$expanded_key" ]]
            then
                printf '%s' "$value"
                return 0
            fi
        done < "$aliases_file"
    fi

    # Fallback: $HOME-relative path
    local home_relative="${resolved#${home_real}/}"
    if [[ $home_relative != "$resolved" && -n $home_relative ]]
    then
        printf '%s' "$home_relative"
        return 0
    fi

    return 1
}

function ntmux3() {
    local detached=
    if [[ $1 == -d ]]
    then
        detached=true
        shift
    fi

    local branch_dir
    if [[ $# == 0 ]]
    then
        if [[ $(pbpaste) == 'ntmux3 '* ]]
        then
            local ntmux3_command_from_clipboard=$(pbpaste)
            local session_name_or_github_pr_url=${ntmux3_command_from_clipboard#ntmux3 }
        else
            local session_name_or_github_pr_url="$(osascript -e 'tell application "Google Chrome" to get URL of active tab of front window')"
            
            if [[ $session_name_or_github_pr_url == https://github.com/*/pull/* ]]
            then
                # Handle PR URL
                local head_ref="$(osascript -e 'tell application "Google Chrome" to execute active tab of front window javascript "document.querySelector(\".head-ref\").textContent"')"
                local expected_pr_md_url=${session_name_or_github_pr_url%/*}
                if [[ $expected_pr_md_url == */pull ]]
                then
                    expected_pr_md_url=${session_name_or_github_pr_url}
                fi
                local pr_path=${session_name_or_github_pr_url#https://github.com/}
                local repo_name=${pr_path#*/}
                repo_name=${repo_name%%/*}
                if [[ $head_ref == *:* ]]
                then
                    # Cross-fork PR: head_ref is "fork-owner:branch-name"
                    local fork_org="${head_ref%%:*}"
                    local fork_branch="${head_ref#*:}"
                    # timvisher_git uses headRepositoryOwner/headRepository/headRefName
                    # which is fork_org/repo/branch (no fork_org prefix on branch)
                    branch_dir="${fork_org}/${repo_name}/${fork_branch}"
                else
                    branch_dir=${pr_path%/pull/*}
                    branch_dir="${branch_dir}/${head_ref}"
                fi
                if [[ -d ${HOME}/git/${branch_dir} ]]
                then
                    session_name_or_github_pr_url="$branch_dir"
                fi
            elif [[ $session_name_or_github_pr_url == https://github.com/*/* ]]
            then
                # Handle repo URL - extract org/repo
                local repo_path=${session_name_or_github_pr_url#https://github.com/}
                # Remove any trailing paths (like /tree/branch, /issues, etc.)
                local org=${repo_path%%/*}
                repo_path=${repo_path#*/}
                local repo=${repo_path%%/*}
                session_name_or_github_pr_url="${org}/${repo}"
            else
                ntmux3__fail "'${session_name_or_github_pr_url}' does not look like a PR or repo URL"
                return
            fi
            history -s ntmux3 "$session_name_or_github_pr_url"
        fi
    else
        local session_name_or_github_pr_url="$1"
        local base_dir_or_target_file="$2"
    fi

    local target_file=
    local local_base_dir=
    local stack_on_base=

    if [[ $session_name_or_github_pr_url != http*://* ]]
    then
        # Expand tilde for detection (command-line args are already expanded,
        # but clipboard/variable values may not be)
        local expanded_arg="$session_name_or_github_pr_url"
        case $expanded_arg in
            '~')   expanded_arg="$HOME" ;;
            '~/'*) expanded_arg="${HOME}/${expanded_arg#'~'/}" ;;
        esac

        # Use timvisher_git is-branch-ish for unified branch-ish detection,
        # replacing the inline org-alias/file/dir gauntlet.  When the arg
        # is a branch-ish, skip local-path resolution so a coincidental
        # CWD match (like ~/dd symlink) doesn't hijack it.
        local is_branch_ish=
        if timvisher_git is-branch-ish "$session_name_or_github_pr_url"
        then
            is_branch_ish=true
        fi

        if [[ -z $is_branch_ish && -f $expanded_arg ]]
        then
            target_file="$expanded_arg"
            expanded_arg="${expanded_arg%/*}"
        fi

        # Detect local (non-worktree) directory for direct path mode
        if [[ -z $is_branch_ish && -d $expanded_arg ]]
        then
            local resolved_arg
            resolved_arg=$(cd "$expanded_arg" && pwd -P) || true
            local home_real_check
            home_real_check=$(cd "$HOME" && pwd -P) || true
            if [[ -n $resolved_arg && $resolved_arg != "${home_real_check}/git/"* ]]
            then
                local_base_dir="$resolved_arg"
            fi
        fi

        local path_session_name
        if [[ -z $is_branch_ish ]]
        then
            path_session_name=$(ntmux3__session_name_from_path "$session_name_or_github_pr_url") || true
        fi
        if [[ -n $path_session_name ]]
        then
            session_name_or_github_pr_url="$path_session_name"
        elif [[ -z $is_branch_ish ]]
        then
            # The directory doesn't exist, but the path may still be
            # under ~/git/.  Strip that prefix so timvisher_git clone
            # receives an org/repo/branch spec instead of an absolute
            # path (which it can't parse).
            local home_real_for_strip
            home_real_for_strip=$(cd "$HOME" && pwd -P) || true
            local git_prefix="${home_real_for_strip}/git/"
            if [[ $expanded_arg == "${git_prefix}"* ]]
            then
                local stripped="${expanded_arg#${git_prefix}}"
                if [[ -z $detached ]]
                then
                    printf 'Create a new worktree at %q? (y/N) ' "$stripped" >&2
                    local reply
                    read -r reply
                    if [[ $reply != [yY] ]]
                    then
                        return 1
                    fi
                fi
                session_name_or_github_pr_url="$stripped"
            fi
        fi
    fi

    # Detect arg 2 as a branch-ish for stacked worktree support.
    if [[ -n $base_dir_or_target_file ]] &&
        timvisher_git is-branch-ish "$base_dir_or_target_file"
    then
        info 'arg 2 is a branch-ish; assuming stacked worktree: %s stacked on %s' \
            "$session_name_or_github_pr_url" "$base_dir_or_target_file"
        stack_on_base="$base_dir_or_target_file"
        base_dir_or_target_file=
    fi

    if [[ -z $detached && -n $TMUX ]]
    then
        echo 'Running ntmux3 inside a tmux Session is not supported' >&2
        return 1
    fi

    # Handle arg2 as file
    if [[ -z $target_file && -f $base_dir_or_target_file ]]
    then
        target_file=$base_dir_or_target_file
        base_dir_or_target_file=${base_dir_or_target_file%/*}
    fi

    # Local path (not a git worktree) — skip timvisher_git clone
    if [[ -n $local_base_dir ]]
    then
        local session_name="$session_name_or_github_pr_url"
        local sanitized_session_name=${session_name//./_}

        info 'local path: sanitized_session_name=%s base_dir=%s' \
            "$sanitized_session_name" "$local_base_dir"

        (
            cd "$local_base_dir" ||
                {
                    ntmux3__fail "Unable to cd to '${local_base_dir}'"
                    return $?
                }

            maybe_set_beads_topic "$local_base_dir"
            timvisher_git clone "$local_base_dir" >/dev/null 2>&1 || true

            if tmux has-session -t="$sanitized_session_name" >/dev/null 2>&1
            then
                if [[ -z $detached ]]
                then
                    tmux attach -t="$sanitized_session_name"
                else
                    printf '%s\n' "$sanitized_session_name"
                    info 'attach with: ntmux3 '\''%s'\''' "$session_name"
                fi
            else
                ntmux ${detached:+-d} "${sanitized_session_name}" "${target_file:-.}"
            fi
        )
        return
    fi

    local branch_dir=$(timvisher_git clone "${session_name_or_github_pr_url}" ${stack_on_base:+"$stack_on_base"}) ||
        ntmux3__fail "Unable to clone ‘${session_name_or_github_pr_url}’"

    [[ -n $branch_dir ]] ||
        {
            ntmux3__fail "Unable to set branch_dir"
            return 1
        }

    local home_real
    home_real=$(cd "$HOME" && pwd -P) ||
        {
            ntmux3__fail "Unable to resolve HOME"
            return 1
        }
    local branch_dir_real
    branch_dir_real=$(cd "$branch_dir" && pwd -P) ||
        {
            ntmux3__fail "Unable to resolve branch_dir"
            return 1
        }
    local session_name=${branch_dir_real#${home_real}/git/}

    (
        {
            [[ -n $branch_dir ]] &&
                cd "${branch_dir}"
        } ||
            {
                ntmux3__fail "Unable to cd to ${branch_dir}"
                return $?
            }

        if [[ -n $expected_pr_md_url ]]
        then
            if ! [[ -r pr.md.url ]]
            then
                echo "Adding pr.md.url with contents ‘${expected_pr_md_url}’" >&2
                tee pr.md.url <<<"${expected_pr_md_url}" >&2
            fi
            pr_md_url=$(< pr.md.url)
            if [[ ${pr_md_url} != ${expected_pr_md_url} ]]
            then
                info 'pr.md.url contents '%s' != expected contents '%s'' "${pr_md_url}" "${expected_pr_md_url}"
                read -rp 'Override? (y/N) ' resp
                if [[ $resp != y ]]
                then
                    info "Exiting at user's request."
                    return
                fi

                info 'Setting pr.md.url contents to expected content '%s'' "${expected_pr_md_url}"
                tee pr.md.url <<<"${expected_pr_md_url}" >&2 ||
                    {
                        error 'Could not set pr.md.url contents'
                        return 1
                    }
            fi
        fi

        maybe_set_beads_topic "$branch_dir_real"

        local sanitized_session_name=${session_name//./_}

        info 'sanitized_session_name=%s' "$sanitized_session_name"

        if tmux has-session -t="$sanitized_session_name" >/dev/null 2>&1
        then
            if [[ -z $detached ]]
            then
                # Attach to Existing Session
                tmux attach -t="$sanitized_session_name"
            else
                printf '%s\n' "$sanitized_session_name"
                info 'attach with: ntmux3 '\''%s'\''' "$session_name"
            fi
        else
            ntmux ${detached:+-d} "${sanitized_session_name}" "${target_file:-.}"
        fi
    )
}

# Local Variables:
# sh-indentation: 4
# End:
