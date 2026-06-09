#!/usr/bin/env bash

# Shared help text and CLI dispatch for *shot commands (claudeshot,
# codexshot, etc.). Source this file, define a `run_shot` function, then
# hand argv to aishot_shot_main:
#
#   source "${SELF_DIR}/../lib/aishot_help.bash"
#   run_shot() { ...; }
#   aishot_shot_main claudeshot Claude run_shot "$@"

aishot_show_help() {
    local cmd=$1
    local name=$2

    cat <<EOF
Usage: ${cmd} <prompt>
       ${cmd} git diff review [--help]
       ${cmd} git diff describe [--help]

Run a one-shot ${name} prompt with streaming progress output.

Subcommands:
  git diff review     Automatically detect uncommitted changes and/or
                      unpushed commits, build a review prompt, and run a
                      one-shot ${name} code review.
  git diff describe   Build a factual changeset inventory (changelog) of
                      the same auto-detected diff and run a one-shot
                      ${name} description. Describes the diff only — no
                      review, critique, or recommendations.

## Agent instructions

When invoking \`${cmd} git diff review\` or \`${cmd} git diff describe\`,
use a subagent to run it. The command handles all prompt construction
internally; just run it:

    Bash({ command: "${cmd} git diff review", run_in_background: true })

For a plain prompt, pass it as the first argument:

    ${cmd} "Explain what this repo does"
EOF
}

aishot_show_review_help() {
    local cmd=$1
    local name=$2

    cat <<EOF
Usage: ${cmd} git diff review

Automatically detect uncommitted changes and/or unpushed commits, build
a review prompt, and run a one-shot ${name} code review with streaming
progress output.

Exits with an error if there is nothing to review.

## Agent instructions

Use a subagent to run this command. The command handles all prompt
construction internally; just run it:

    Bash({ command: "${cmd} git diff review", run_in_background: true })

GOLDEN RULE: EVERY finding the reviewer reports is YOUR responsibility.
Nothing in the diff is "pre-existing" or "not our commit". If it is in
the diff, it ships with your work. Investigate and fix ALL findings.
Never dismiss a finding. Never say "not actionable" or "good to note".
EOF
}

aishot_show_describe_help() {
    local cmd=$1
    local name=$2

    cat <<EOF
Usage: ${cmd} git diff describe

Automatically detect uncommitted changes and/or unpushed commits, build
a factual changeset-inventory (changelog) prompt, and run a one-shot
${name} description with streaming progress output.

This DESCRIBES the diff; it does not review it. The output is the kind of
entry you would write in a CHANGELOG — no critique, quality judgment, or
recommendations.

Exits with an error if there is nothing to describe.

## Agent instructions

Use a subagent to run this command. The command handles all prompt
construction internally; just run it:

    Bash({ command: "${cmd} git diff describe", run_in_background: true })
EOF
}

# Full CLI dispatch shared by the per-shot wrappers. Keeps the command
# surface (git diff review / git diff describe, --help, stdin, plain
# prompt) identical across claudeshot/codexshot/geminishot.
#   $1 = command name for help text (e.g. "claudeshot")
#   $2 = display name (e.g. "Claude")
#   $3 = name of the caller's run_shot function (reads the prompt on
#        stdin, runs the one-shot tool)
#   $4.. = the wrapper's own "$@"
aishot_shot_main() {
    local cmd=$1
    local name=$2
    local run=$3
    shift 3

    case "${1:-}" in
        git)
            shift
            if [[ ${1:-} != diff ]]
            then
                printf "Error: Unknown '%s git' subcommand '%s'. Expected: diff.\n" \
                    "$cmd" "${1:-}" >&2
                aishot_show_help "$cmd" "$name" >&2
                return 1
            fi
            shift
            case "${1:-}" in
                review)
                    shift
                    if [[ ${1:-} == --help || ${1:-} == -h ]]
                    then
                        aishot_show_review_help "$cmd" "$name"
                        return 0
                    fi
                    aishot git diff review make-prompt | "$run"
                    ;;
                describe)
                    shift
                    if [[ ${1:-} == --help || ${1:-} == -h ]]
                    then
                        aishot_show_describe_help "$cmd" "$name"
                        return 0
                    fi
                    aishot git diff describe make-prompt | "$run"
                    ;;
                *)
                    printf "Error: Unknown '%s git diff' subcommand '%s'. Expected: review, describe.\n" \
                        "$cmd" "${1:-}" >&2
                    aishot_show_help "$cmd" "$name" >&2
                    return 1
                    ;;
            esac
            ;;
        --help|-h)
            aishot_show_help "$cmd" "$name"
            return 0
            ;;
        "")
            # No arg — read from stdin if piped, otherwise show help.
            if [[ -t 0 ]]
            then
                aishot_show_help "$cmd" "$name" >&2
                return 1
            fi
            aishot make-prompt | "$run"
            ;;
        *)
            echo "$1" | aishot make-prompt | "$run"
            ;;
    esac
}
