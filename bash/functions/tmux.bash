shopt -s extglob

function ntmux3__define_code() {
    [[ -v $1 ]] || declare -gr "$1=$2"
}

ntmux3__define_code NTMUX3_CODE_STARTED ntmux3_started
ntmux3__define_code NTMUX3_CODE_FAILED ntmux3_failed
ntmux3__define_code NTMUX3_CODE_SESSION_READY ntmux3_session_ready
ntmux3__define_code NTMUX3_CODE_WORKTREE_BUILDING ntmux3_worktree_building
ntmux3__define_code NTMUX3_CODE_WORKTREE_READY ntmux3_worktree_ready
ntmux3__define_code NTMUX3_CODE_TERMINAL_OPEN_FAILED ntmux3_terminal_open_failed
ntmux3__define_code NTMUX3_CODE_TERMINAL_CLOSED ntmux3_terminal_closed
ntmux3__define_code NTMUX3_CODE_TERMINAL_LOG_LOST ntmux3_terminal_log_lost
ntmux3__define_code NTMUX3_CODE_TERMINAL_TIMEOUT ntmux3_terminal_timeout
ntmux3__define_code NTMUX3_CODE_TERMINAL_NOT_STARTED ntmux3_terminal_not_started

function ntmux3__aictl_listening() {
    declare -F aictl_listening &>/dev/null && aictl_listening
}

function ntmux3__emit_started() {
    if [[ -n ${TIMVISHER_AICTL_LOG:-} ]] && declare -F aictl_info &>/dev/null
    then
        aictl_info \
            --code "$NTMUX3_CODE_STARTED" \
            --message "ntmux3 started in process ${BASHPID}." \
            --data "{\"pid\":${BASHPID}}" \
            --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
    fi
}

function ntmux3__emit_session_ready() {
    local session_name=$1 message=$2

    ntmux3__aictl_listening || return 0

    if ! tmux has-session -t="$session_name" >/dev/null 2>&1
    then
        ntmux3__fail "tmux session '${session_name}' does not exist, so it cannot be reported as ready."
        return 1
    fi

    local session_path data
    session_path=$(tmux display-message -p -t="$session_name" '#{session_path}' 2>/dev/null) || true
    data=$(jq -nc --arg session "$session_name" --arg path "$session_path" \
        '{session: $session, path: $path}') ||
        {
            ntmux3__fail "jq is required to report tmux session '${session_name}' as ready."
            return 1
        }
    aictl_info \
        --code "$NTMUX3_CODE_SESSION_READY" \
        --message "$message" \
        --data "$data" \
        --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
    ntmux3__mark_verdict
}

function ntmux3__attach() {
    local session_name=$1

    ntmux3__emit_session_ready "$session_name" \
        "tmux session '${session_name}' is ready; attaching." ||
        return 1

    tmux attach -t="$session_name"
}

function ntmux3__mark_verdict() {
    if [[ -n ${ntmux3__verdict_marker:-} ]]
    then
        printf 'x' >> "$ntmux3__verdict_marker"
    fi
}

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

        local nofile_soft
        nofile_soft=$(ulimit -Sn)
        if [[ $nofile_soft != unlimited ]] && (( nofile_soft < 1024 ))
        then
            ulimit -Sn 1024
        fi

        # tmux -vvvv new-session -d -s "$session_name" -n editor "$default_command" # for debugging
        if ! env -u TIMVISHER_AICTL_LOG tmux new-session -d -s "$session_name" -n editor "$default_command"
        then
            echo "# Unable to create tmux session $session_name." >&2
            return 1
        fi
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
    ) || return 1

    if [[ -z $detached ]]
    then
        ntmux3__attach "$session_name"
    else
        ntmux3__emit_session_ready "$session_name" "tmux session '${session_name}' is ready." ||
            return 1
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
            ntmux3__attach "$session_name"
        else
            ntmux3__emit_session_ready "$session_name" "tmux session '${session_name}' is ready." ||
                return 1
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
    echo 'Usage: ntmux3 [-d | -T] [GitHub PR URL | org/repo[/branch] | path] [file]' >&2
    echo '       ntmux3 [-d | -T] org/repo/branch branch-ish' >&2
    echo '  -d creates the session detached.  -T runs ntmux3 in a new terminal window; under an agent it' >&2
    echo '  waits for the session and reports it like -d.' >&2
    echo '  org may be an org alias.  An existing file as arg 2 opens in the editor.' >&2
    echo '  The second form stacks a new worktree for org/repo/branch on branch-ish; the target must be a' >&2
    echo '  new branch.  branch-ish may be relative: a bare branch name is resolved against org/repo.' >&2
    return 1
}

function ntmux3__fail() {
    echo "$1" >&2
    if ntmux3__aictl_listening
    then
        aictl_error \
            --code "$NTMUX3_CODE_FAILED" \
            --message "$1" \
            --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
        ntmux3__mark_verdict
    fi
    return 1
}

function ntmux3__classify_instruction() {
    local instruction
    instruction=$(aictl_parse "$1") || return 1

    jq -c \
        --arg started "$NTMUX3_CODE_STARTED" \
        --arg session_ready "$NTMUX3_CODE_SESSION_READY" \
        --arg failed "$NTMUX3_CODE_FAILED" \
        '((.data | objects) // {}) as $data
         | if .code == $started then
             {state: "started", pid: (($data.pid | numbers) // null)}
           elif .code == $session_ready then
             if (($data.session | strings) // "") != "" then
               {state: "ready", session: $data.session, path: $data.path}
             else
               {state: "failed", code: .code, message: "\(.code) carried no session name"}
             end
           elif .code == $failed then
             {state: "failed", code: .code, message: .message}
           else
             {state: "progress", code: .code}
           end' <<<"$instruction"
}

function ntmux3__terminal_number() {
    local value=$1 default=$2

    if [[ $value =~ ^[0-9]+$ ]] && (( 0 < 10#$value ))
    then
        printf '%s' "$(( 10#$value ))"
    else
        printf '%s' "$default"
    fi
}

function ntmux3__wait_for_terminal() {
    local log=$1
    local poll deadline startup_deadline
    poll=$(ntmux3__terminal_number "${TIMVISHER_NTMUX3_TERMINAL_POLL:-}" 5)
    deadline=$(ntmux3__terminal_number "${TIMVISHER_NTMUX3_TERMINAL_DEADLINE:-}" 3600)
    startup_deadline=$(ntmux3__terminal_number "${TIMVISHER_NTMUX3_TERMINAL_STARTUP_DEADLINE:-}" 60)
    (( deadline += SECONDS ))
    (( startup_deadline += SECONDS ))

    local tail_fd
    exec {tail_fd}< <(exec tail -n +1 -F "$log" 2>/dev/null)
    ntmux3__tail_pid=$!

    local started='' started_pid='' partial='' line instruction verdict timeout rc result=''
    while [[ -z $result ]]
    do
        if (( deadline <= SECONDS ))
        then
            aictl_error \
                --code "$NTMUX3_CODE_TERMINAL_TIMEOUT" \
                --message "ntmux3 in the terminal window did not report a session or a failure in time. It may still be running; check the window." \
                --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
            result=1
            break
        fi

        if [[ -z $started ]] && (( startup_deadline <= SECONDS ))
        then
            aictl_error \
                --code "$NTMUX3_CODE_TERMINAL_NOT_STARTED" \
                --message "ntmux3 never reported starting in the terminal window. The window may not have opened a bash shell with ntmux3 loaded; check it." \
                --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
            result=1
            break
        fi

        timeout=$(( deadline - SECONDS ))
        if [[ -z $started ]] && (( startup_deadline - SECONDS < timeout ))
        then
            timeout=$(( startup_deadline - SECONDS ))
        fi
        if (( poll < timeout ))
        then
            timeout=$poll
        fi
        if (( timeout < 1 ))
        then
            timeout=1
        fi

        rc=0
        IFS= read -r -t "$timeout" -u "$tail_fd" line || rc=$?
        if (( rc == 0 ))
        then
            line=$partial$line
            partial=''
            instruction=$(aictl_parse "$line") || continue
            printf '%s\n' "$instruction" >&2
            verdict=$(ntmux3__classify_instruction "$instruction") || continue
            case $(jq -r .state <<<"$verdict") in
                started)
                    started=true
                    started_pid=$(jq -r '.pid // empty' <<<"$verdict")
                    ;;
                ready)
                    jq -r .session <<<"$verdict"
                    result=0
                    ;;
                failed)
                    result=1
                    ;;
            esac
        elif (( 128 < rc ))
        then
            partial+=$line
            if [[ -n $started_pid ]] && ! kill -0 "$started_pid" 2>/dev/null
            then
                aictl_error \
                    --code "$NTMUX3_CODE_TERMINAL_CLOSED" \
                    --message "ntmux3 in the terminal window (process ${started_pid}) exited before reporting a session or a failure." \
                    --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
                result=1
            fi
        else
            aictl_error \
                --code "$NTMUX3_CODE_TERMINAL_LOG_LOST" \
                --message "Lost the instruction log '${log}' before ntmux3 in the terminal window reported a session or a failure." \
                --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
            result=1
        fi
    done

    exec {tail_fd}<&-
    return "$result"
}

function ntmux3__terminal() (
    local log='' ntmux3__tail_pid=''
    trap '[[ -n $ntmux3__tail_pid ]] && kill "$ntmux3__tail_pid" 2>/dev/null; [[ -n $log ]] && rm -f -- "$log"' EXIT
    trap 'exit 130' INT
    trap 'exit 129' HUP
    trap 'exit 143' TERM

    local command
    command="cd $(printf '%q' "$PWD") && "

    if [[ -n ${TIMVISHER_AGENT:-} ]]
    then
        if ! declare -F aictl_parse &>/dev/null || ! declare -F aictl_error &>/dev/null
        then
            echo 'ntmux3 -T needs the aictl functions (~/.functions/aictl.bash) to report back to an agent.' >&2
            return 1
        fi
        log=$(mktemp "${TMPDIR:-/tmp}/ntmux3-terminal.XXXXXX") ||
            {
                ntmux3__fail 'Unable to create the instruction log for ntmux3 -T'
                return 1
            }
        command+="TIMVISHER_AICTL_LOG=$(printf '%q' "$log") "
    fi

    command+=ntmux3
    if (( 0 < $# ))
    then
        command+=$(printf ' %q' "$@")
    fi

    local applescript_command=${command//\\/\\\\}
    applescript_command=${applescript_command//\"/\\\"}

    if ! osascript -e "tell script \"timvisher Terminal\" to runCommandInteractively(\"${applescript_command}\")" >/dev/null
    then
        if declare -F aictl_error &>/dev/null
        then
            aictl_error \
                --code "$NTMUX3_CODE_TERMINAL_OPEN_FAILED" \
                --message "Unable to open a terminal window running: ${command}" \
                --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
        else
            echo "Unable to open a terminal window running: ${command}" >&2
        fi
        return 1
    fi

    if [[ -z $log ]]
    then
        return 0
    fi

    ntmux3__wait_for_terminal "$log"
)

# Return 0 if $1 is a working tree backed by our managed trunk cache
# (a worktree linked to a bare repo under
# ~/.cache/timvisher_git_worktrees/repo_trunks), else 1.  This mirrors
# timvisher_git's own classification (its repo_trunks_dir + the
# git-common-dir prefix test in ensure_existing_repo): a managed worktree
# is one whose git common dir lives under that cache root.  The check is
# cheap — a couple of local `git rev-parse` calls, no network.
function ntmux3__is_managed_worktree() {
    local dir=$1
    local common_dir trunks_dir

    common_dir=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return 1
    # --git-common-dir may be relative to $dir; canonicalize from there.
    common_dir=$(cd "$dir" && cd "$common_dir" && pwd -P 2>/dev/null) || return 1

    trunks_dir="${HOME}/.cache/timvisher_git_worktrees/repo_trunks"
    # Canonicalize the cache root too, so a symlinked $HOME (or cache) on
    # either side still produces an apples-to-apples prefix match.  If it
    # doesn't exist yet, nothing can be managed, so the raw value is fine.
    if [[ -d $trunks_dir ]]
    then
        trunks_dir=$(cd "$trunks_dir" && pwd -P 2>/dev/null) ||
            trunks_dir="${HOME}/.cache/timvisher_git_worktrees/repo_trunks"
    fi

    [[ $common_dir == "${trunks_dir}/"* ]]
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

# Resolve the tmux session name for a path using the full mechanism: try
# ntmux3__session_name_from_path first (file/dir aliases, the ~/git/
# prefix, and $HOME-relative names), then fall back to a canonicalized
# ~/git/-relative name, then basename.  Both the managed-worktree path
# and the existing-repo/open path resolve names through here so they stay
# identical.
#   $1 — path to look up (may be a file, so file-level aliases can win)
#   $2 — directory to fall back on for basename (defaults to $1)
function ntmux3__resolve_session_name() {
    local lookup=$1
    local fallback_dir=${2:-$1}

    local name
    name=$(ntmux3__session_name_from_path "$lookup") || true
    if [[ -n $name ]]
    then
        printf '%s' "$name"
        return 0
    fi

    local fallback_real
    fallback_real=$(cd "$fallback_dir" && pwd -P) || true
    if [[ -n $fallback_real ]]
    then
        local home_real
        home_real=$(cd "$HOME" && pwd -P) || true
        name=${fallback_real#${home_real}/git/}
        if [[ $name == "$fallback_real" ]]
        then
            name=$(basename "$fallback_real")
        fi
    else
        name=$(basename "$fallback_dir")
    fi
    printf '%s' "$name"
}

function ntmux3__history() {
    if [[ -n ${ntmux3__state_dir:-} ]]
    then
        printf '%s' "$1" > "${ntmux3__state_dir}/history"
    else
        history -s ntmux3 "$1"
    fi
}

function ntmux3__report_exit() {
    local status=$1 why=$2

    if [[ ! -s $ntmux3__verdict_marker ]]
    then
        ntmux3__fail "ntmux3 ${why} before a tmux session was ready."
    fi
    return "$status"
}

function ntmux3__reporting_run() (
    local ntmux3__verdict_marker="${ntmux3__state_dir}/verdict"

    ntmux3__emit_started

    trap 'ntmux3__report_exit 130 "was interrupted"; exit 130' INT
    trap 'ntmux3__report_exit 129 "was hung up"; exit 129' HUP
    trap 'ntmux3__report_exit 143 "was terminated"; exit 143' TERM

    local status=0
    ntmux3__main "$@" || status=$?
    ntmux3__report_exit "$status" "exited with status ${status}"
)

function ntmux3__reporting() {
    local ntmux3__state_dir
    if ! ntmux3__state_dir=$(mktemp -d "${TMPDIR:-/tmp}/ntmux3-state.XXXXXX")
    then
        ntmux3__emit_started
        ntmux3__fail 'Unable to create the state directory ntmux3 needs to report its outcome.'
        return 1
    fi

    local status=0
    ntmux3__reporting_run "$@" || status=$?

    if [[ -s ${ntmux3__state_dir}/history ]]
    then
        history -s ntmux3 "$(< "${ntmux3__state_dir}/history")"
    fi
    rm -rf -- "$ntmux3__state_dir"
    return "$status"
}

function ntmux3() {
    if [[ ${1-} == -T ]]
    then
        shift
        if [[ ${1-} == -d ]]
        then
            ntmux3__fail 'ntmux3 -T cannot be combined with -d: the terminal window has to attach to report that its session is ready.'
            return
        fi
        ntmux3__terminal "$@"
        return
    fi

    if [[ ${1-} == -d && ${2-} == -T ]]
    then
        ntmux3__fail 'ntmux3 -d cannot be combined with -T: the terminal window has to attach to report that its session is ready.'
        return
    fi

    if [[ -n ${TIMVISHER_AICTL_LOG:-} ]]
    then
        ntmux3__reporting "$@"
    else
        ntmux3__main "$@"
    fi
}

function ntmux3__main() {
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
            clone_target="$(osascript -e 'tell script "timvisher Browser" to getActiveTabUrl()')"

            if [[ $clone_target == https://github.com/*/pull/* ]]
            then
                # Handle PR URL
                local head_ref
                head_ref="$(osascript -e 'tell script "timvisher Browser" to executeJsInActiveTab("document.querySelector(\".head-ref\").textContent")')"
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
            ntmux3__history "$clone_target"
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
        if [[ -f $base_dir_or_target_file ]]
        then
            if [[ -z $target_file ]]
            then
                target_file="$base_dir_or_target_file"
            fi
        elif timvisher_git is-branch-ish "$base_dir_or_target_file" "$clone_target"
        then
            info 'arg 2 is a branch-ish; stacking %s on %s' \
                "$clone_target" "$base_dir_or_target_file"
            stack_on_base="$base_dir_or_target_file"
        elif ntmux3__aictl_listening
        then
            aictl_notice \
                --code "ntmux3_arg2_ignored" \
                --message "arg 2 '${base_dir_or_target_file}' is neither an existing file nor a branch-ish, so it was ignored and nothing is stacked." \
                --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
        else
            warn "arg 2 '%s' is neither an existing file nor a branch-ish; ignoring it" \
                "$base_dir_or_target_file"
        fi
    fi

    if [[ -z $detached && -n $TMUX ]]
    then
        if ntmux3__aictl_listening
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
        # Resolve via the shared resolver so an existing repo is named by
        # exactly the same mechanisms as a managed worktree.  Look up the
        # original file path when the user passed one so that file-level
        # aliases in ntmux3_path_aliases win over the parent-directory
        # match; fall back on the directory for basename.
        session_name=$(ntmux3__resolve_session_name "${target_file:-$dir}" "$dir")
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
                    ntmux3__attach "$sanitized_session_name"
                else
                    ntmux3__emit_session_ready "$sanitized_session_name" \
                        "tmux session '${sanitized_session_name}' is ready." ||
                        return 1
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

    # --- Existing non-managed working tree: just open a session ---
    # If the target is already a checked-out git working tree that is NOT
    # one of our managed worktrees, ntmux3 must do nothing to it but
    # (re)attach a tmux session — it must not route through
    # `timvisher_git clone`.  clone() -> ensure_worktree() calls
    # cache_trunk() unconditionally, deriving the origin from
    # github.com/<org>/<repo>; for a foreign repo that is already present
    # locally (e.g. a clone of a non-GitHub remote) that fetch 404s and
    # the clone dies.
    #
    # Managed worktrees (git common dir under the trunk cache) deliberately
    # fall through to clone so they still get the full managed treatment
    # (fetch, tracking, stacking).  Distinguishing the two is cheap: a
    # couple of local `git rev-parse` calls, no network.
    #
    # Skipped when a stack base is requested (that path needs clone).  PR
    # URLs are http:// so they never match the absolute-path test.
    if [[ -z $stack_on_base ]] &&
        [[ $clone_target == /* && -d $clone_target ]] &&
        git -C "$clone_target" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        ! ntmux3__is_managed_worktree "$clone_target"
    then
        ntmux3__open_nonrepo_dir "$clone_target"
        return
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

    # Tell an agent up front that this is a long-running op and that the
    # worktree it produces is NOT ready until the completion instruction.
    # The worktree is built in a hidden temp dir and only moved to its
    # canonical path when fully ready, so the canonical path does not even
    # exist until then — editing earlier races the build (ide-8hi).
    if ntmux3__aictl_listening
    then
        aictl_notice \
            --code "$NTMUX3_CODE_WORKTREE_BUILDING" \
            --message "Creating a worktree for '${clone_target}' — a long-running operation (clone, checkout, maintenance, any stacking). Do NOT use or edit the worktree until you see the 'ntmux3_worktree_ready' instruction with its path." \
            --reason "ntmux3 builds the worktree in a hidden temp dir and moves it into its canonical path only when fully ready, so the canonical path does not exist until then. Touching it earlier races the build and edits can be clobbered (e.g. by a stacking reset --hard)." \
            --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
    fi

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

    # The clone returns only once the worktree is fully built and moved
    # into place, so this is the readiness signal the opener promised.
    if ntmux3__aictl_listening
    then
        aictl_info \
            --code "$NTMUX3_CODE_WORKTREE_READY" \
            --message "Worktree ready at '${branch_dir}'. It is now safe to use and edit." \
            --doc "ai/HOME/.agents/skills/worktree/SKILL.md"
    fi

    # Derive session name from the returned directory (shared resolver).
    local session_name
    session_name=$(ntmux3__resolve_session_name "$branch_dir")

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
                ntmux3__attach "$sanitized_session_name"
            else
                ntmux3__emit_session_ready "$sanitized_session_name" \
                    "tmux session '${sanitized_session_name}' is ready." ||
                    return 1
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
