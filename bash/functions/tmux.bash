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

function ntmux3__handle_bd_topic() {
    local dir=$1
    local topic_rel=$2
    local target_file=$3

    if [[ ! -d $dir/.beads ]]
    then
        info 'creating bd topic %s' "$topic_rel"
        # Run from a neutral CWD so `timvisher_bd_topics new` doesn't
        # auto-subscribe whatever repo the user invoked ntmux3 from.
        (cd / && command timvisher_bd_topics new "$topic_rel") ||
            {
                ntmux3__fail "timvisher_bd_topics new '${topic_rel}' failed"
                return 1
            }
    fi

    if [[ -n $target_file && ! -f $target_file ]]
    then
        touch "$target_file" ||
            {
                ntmux3__fail "Unable to create '${target_file}'"
                return 1
            }
    fi
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
    local file_path=

    # Handle file paths by using the parent directory.  Capture the
    # absolute, symlink-resolved file path so file-level aliases match
    # the same canonical form `cd ... && pwd -P` produces below.  Bare
    # filenames (no slash) are treated as CWD-relative.
    if [[ -f $candidate_path && ! -d $candidate_path ]]
    then
        local input_basename input_parent file_dir
        input_basename=$(basename "$candidate_path")
        if [[ $candidate_path == */* ]]
        then
            input_parent="${candidate_path%/*}"
        else
            input_parent="."
        fi
        file_dir=$(cd "$input_parent" 2>/dev/null && pwd -P) || true
        if [[ -n $file_dir ]]
        then
            file_path="${file_dir}/${input_basename}"
        fi
        candidate_path="$input_parent"
    fi

    if [[ ! -d $candidate_path ]]
    then
        return 1
    fi

    local resolved
    resolved=$(cd "$candidate_path" 2>/dev/null && pwd -P) || return 1

    local home_real
    home_real=$(cd "$HOME" && pwd -P) || return 1

    local config_dir=${XDG_CONFIG_HOME:-${HOME}/.config}/timvisher/ide
    local aliases_file=${config_dir}/ntmux3_path_aliases

    # File-level aliases beat every other rule: most-specific wins.
    # Only consulted when the input was a file.  We canonicalize the
    # alias key the same way we canonicalized $file_path (resolve the
    # parent dir's symlinks, append basename) so symlinks in either the
    # alias key or the input don't silently bypass the match.
    if [[ -n $file_path && -r $aliases_file ]]
    then
        local line key value expanded_key key_dir key_basename key_parent
        while IFS= read -r line || [[ -n $line ]]
        do
            [[ -z $line ]] && continue
            [[ $line == \#* ]] && continue
            key=${line%%=*}
            value=${line#*=}
            case $key in
                '~')   expanded_key="$home_real" ;;
                '~/'*) expanded_key="${home_real}/${key#'~'/}" ;;
                *)     expanded_key="$key" ;;
            esac
            if [[ $expanded_key == */* ]]
            then
                key_basename=$(basename "$expanded_key")
                key_parent="${expanded_key%/*}"
                key_dir=$(cd "$key_parent" 2>/dev/null && pwd -P) || key_dir=
                if [[ -n $key_dir ]]
                then
                    expanded_key="${key_dir}/${key_basename}"
                fi
            fi
            if [[ $file_path == "$expanded_key" ]]
            then
                printf '%s' "$value"
                return 0
            fi
        done < "$aliases_file"
    fi

    # Try ~/git/ prefix first (existing worktree path)
    local relative="${resolved#${home_real}/git/}"
    if [[ $relative != "$resolved" && -n $relative ]]
    then
        printf '%s' "$relative"
        return 0
    fi

    # Try path aliases from config
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

    local clone_target=
    local target_file=
    local stack_on_base=
    local expected_pr_md_url=
    local base_dir_or_target_file=

    # --- Parse arguments ---
    if [[ $# == 0 ]]
    then
        if [[ $(pbpaste) == 'ntmux3 '* ]]
        then
            local ntmux3_command_from_clipboard
            ntmux3_command_from_clipboard=$(pbpaste)
            clone_target=${ntmux3_command_from_clipboard#ntmux3 }
        else
            clone_target="$(osascript -e 'tell application "Google Chrome" to get URL of active tab of front window')"

            if [[ $clone_target == https://github.com/*/pull/* ]]
            then
                # Handle PR URL
                local head_ref
                head_ref="$(osascript -e 'tell application "Google Chrome" to execute active tab of front window javascript "document.querySelector(\".head-ref\").textContent"')"
                expected_pr_md_url=${clone_target%/*}
                if [[ $expected_pr_md_url == */pull ]]
                then
                    expected_pr_md_url=${clone_target}
                fi
                local pr_path=${clone_target#https://github.com/}
                local repo_name=${pr_path#*/}
                repo_name=${repo_name%%/*}
                local pr_branch_dir
                if [[ $head_ref == *:* ]]
                then
                    # Cross-fork PR: head_ref is "fork-owner:branch-name"
                    local fork_org="${head_ref%%:*}"
                    local fork_branch="${head_ref#*:}"
                    pr_branch_dir="${fork_org}/${repo_name}/${fork_branch}"
                else
                    pr_branch_dir=${pr_path%/pull/*}
                    pr_branch_dir="${pr_branch_dir}/${head_ref}"
                fi
                # Optimization: if the worktree already exists, use the
                # branch-ish shorthand to avoid a gh API call.
                if [[ -d ${HOME}/git/${pr_branch_dir} ]]
                then
                    clone_target="$pr_branch_dir"
                fi
            elif [[ $clone_target == https://github.com/*/* ]]
            then
                # Handle repo URL - extract org/repo
                local repo_path=${clone_target#https://github.com/}
                local org=${repo_path%%/*}
                repo_path=${repo_path#*/}
                local repo=${repo_path%%/*}
                clone_target="${org}/${repo}"
            else
                ntmux3__fail "'${clone_target}' does not look like a PR or repo URL"
                return
            fi
            history -s ntmux3 "$clone_target"
        fi
    else
        clone_target="$1"
        base_dir_or_target_file="${2:-}"
    fi

    # --- Pre-processing for non-URL targets ---
    if [[ $clone_target != http*://* ]]
    then
        # Expand tilde (command-line args are already expanded, but
        # clipboard/variable values may not be)
        case $clone_target in
            '~')   clone_target="$HOME" ;;
            '~/'*) clone_target="${HOME}/${clone_target#'~'/}" ;;
        esac

        # Resolve relative FILE paths to absolute (editor needs full path).
        # Relative DIRECTORIES are left as-is so clone() can try remote
        # first — resolving here would turn "org/repo" into an absolute
        # path that bypasses remote-first resolution.
        if [[ $clone_target != /* && -f $clone_target ]]
        then
            local abs_dir
            abs_dir=$(cd "$(dirname "$clone_target")" && pwd -P) || true
            if [[ -n $abs_dir ]]
            then
                clone_target="${abs_dir}/$(basename "$clone_target")"
            fi
        fi

        # File-path inputs: strip to parent dir, preserve file for editor
        if [[ -f $clone_target ]]
        then
            target_file="$clone_target"
            clone_target="$(dirname "$clone_target")"
        fi
    fi

    # Handle arg2: stacked worktree or file
    if [[ -n $base_dir_or_target_file ]]
    then
        if timvisher_git is-branch-ish "$base_dir_or_target_file"
        then
            info 'arg 2 is a branch-ish; assuming stacked worktree: %s stacked on %s' \
                "$clone_target" "$base_dir_or_target_file"
            stack_on_base="$base_dir_or_target_file"
        elif [[ -z $target_file && -f $base_dir_or_target_file ]]
        then
            target_file="$base_dir_or_target_file"
        fi
    fi

    if [[ -z $detached && -n $TMUX ]]
    then
        if [[ -n ${TIMVISHER_AGENT:-} ]] && declare -F aictl_error &>/dev/null
        then
            aictl_error \
                --code "ntmux3_inside_tmux" \
                --message "ntmux3 cannot attach a new tmux session from inside an existing one — use -d for detached mode." \
                --reason "Without -d, ntmux3 tries to replace the current tmux client, which isn't supported. Detached mode creates the worktree + session without attaching, which is what agents want anyway." \
                --doc "ai/HOME/.agents/skills/worktree/SKILL.md" \
                --suggestion "ntmux3 -d ${clone_target:-<org/repo/branch>}"
        else
            echo 'Running ntmux3 inside a tmux session is not supported (pass -d for detached mode)' >&2
        fi
        return 1
    fi

    # --- Non-git directory: open as local session ---
    # Only fires as a pre-clone fast path for absolute paths that are
    # clearly not remotes and not under ~/git/.  Relative paths (which
    # could be org/repo shorthands) always go through clone first;
    # non-git dirs are handled as a post-clone fallback below.
    local home_real_ngd
    home_real_ngd=$(cd "$HOME" && pwd -P 2>/dev/null) || true

    ntmux3__open_nonrepo_dir() {
        local dir=$1
        local session_name
        # Use the original file path when the user passed one so that
        # file-level aliases in ntmux3_path_aliases get a chance to win
        # over the parent-directory match.
        session_name=$(ntmux3__session_name_from_path "${target_file:-$dir}") || true
        if [[ -z $session_name ]]
        then
            session_name=$(basename "$dir")
        fi
        local sanitized_session_name=${session_name//./_}

        info 'local path: sanitized_session_name=%s base_dir=%s' \
            "$sanitized_session_name" "$dir"

        (
            cd "$dir" ||
                {
                    ntmux3__fail "Unable to cd to '${dir}'"
                    return $?
                }

            maybe_set_beads_topic "$dir"

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
    }

    # --- bd_topics path: handle as standalone beads topic ---
    # If the target path resolves under the configured bd topics root,
    # treat it as a topic directory rather than a git clone target.
    # Creates the topic via `timvisher_bd_topics new` if missing.
    if [[ $clone_target == /* ]] &&
        command -v timvisher_bd_topics >/dev/null 2>&1
    then
        local bd_candidate=${clone_target%/}
        # Normalize /.beads[/...] suffixes so a user passing the topic's
        # internals (e.g. `.beads/` itself) still routes to the topic dir.
        bd_candidate=${bd_candidate%%/.beads*}
        local bd_dir=$bd_candidate
        local bd_file=$target_file
        # Any trailing path component with an extension is treated as a
        # file; otherwise the whole path is treated as the topic dir.
        if [[ -z $bd_file && ${bd_candidate##*/} == *.* && ! -d $bd_candidate ]]
        then
            bd_file=$bd_candidate
            bd_dir=${bd_candidate%/*}
        fi
        local bd_topic_rel
        if bd_topic_rel=$(command timvisher_bd_topics resolve "$bd_dir")
        then
            ntmux3__handle_bd_topic "$bd_dir" "$bd_topic_rel" "$bd_file" ||
                return $?
            clone_target=$bd_dir
            target_file=$bd_file
            ntmux3__open_nonrepo_dir "$clone_target"
            return
        fi
    fi

    if [[ $clone_target == /* && -d $clone_target ]] &&
        [[ -z $home_real_ngd || $clone_target != "${home_real_ngd}/git/"* ]] &&
        ! git -C "$clone_target" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        ! [[ $(git -C "$clone_target" rev-parse --is-bare-repository 2>/dev/null) == true ]]
    then
        ntmux3__open_nonrepo_dir "$clone_target"
        return
    fi

    # --- Everything else: pass to timvisher_git clone ---
    # Remote is always tried first.  If clone fails on a non-git
    # directory (e.g. relative path that isn't an org/repo shorthand),
    # fall back to opening it as a local session.
    local branch_dir
    branch_dir=$(TIMVISHER_NTMUX=1 timvisher_git clone "$clone_target" ${stack_on_base:+"$stack_on_base"}) || {
        if [[ -d $clone_target ]] &&
            ! git -C "$clone_target" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
            ! [[ $(git -C "$clone_target" rev-parse --is-bare-repository 2>/dev/null) == true ]]
        then
            ntmux3__open_nonrepo_dir "$clone_target"
            return
        fi
        ntmux3__fail "Unable to clone '${clone_target}'"
        return
    }

    [[ -n $branch_dir ]] ||
        {
            ntmux3__fail "Unable to set branch_dir"
            return 1
        }

    # Derive session name from the returned directory
    local session_name
    session_name=$(ntmux3__session_name_from_path "$branch_dir") || true
    if [[ -z $session_name ]]
    then
        # Fallback: ~/git/-relative path or basename
        local branch_dir_real
        branch_dir_real=$(cd "$branch_dir" && pwd -P) || true
        if [[ -n $branch_dir_real ]]
        then
            local home_real
            home_real=$(cd "$HOME" && pwd -P) || true
            session_name=${branch_dir_real#${home_real}/git/}
            if [[ $session_name == "$branch_dir_real" ]]
            then
                session_name=$(basename "$branch_dir_real")
            fi
        else
            session_name=$(basename "$branch_dir")
        fi
    fi

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
                echo "Adding pr.md.url with contents '${expected_pr_md_url}'" >&2
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

        local branch_dir_real
        branch_dir_real=$(cd . && pwd -P) || true
        maybe_set_beads_topic "${branch_dir_real:-.}"

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
