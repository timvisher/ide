#!/usr/bin/env bash

# Shared help text for *shot commands (claudeshot, codexshot, etc.).
# Source this file and call aishot_show_help / aishot_show_review_help.
#
# Usage:
#   source "${SELF_DIR}/../lib/aishot_help.bash"
#   aishot_show_help "claudeshot" "Claude"
#   aishot_show_review_help "claudeshot" "Claude"

aishot_show_help() {
    local cmd=$1
    local name=$2

    cat <<EOF
Usage: ${cmd} <prompt>
       ${cmd} review [--help]

Run a one-shot ${name} prompt with streaming progress output.

Subcommands:
  review    Automatically detect uncommitted changes and/or unpushed
            commits, build a review prompt, and run a one-shot ${name}
            code review.

## Agent instructions

When invoking \`${cmd} review\`, use a subagent to run it — the review
can take 1-3 minutes. The command handles all prompt construction
internally; just run it:

    Bash({ command: "${cmd} review", run_in_background: true })

For a plain prompt, pass it as the first argument:

    ${cmd} "Explain what this repo does"
EOF
}

aishot_show_review_help() {
    local cmd=$1
    local name=$2

    cat <<EOF
Usage: ${cmd} review

Automatically detect uncommitted changes and/or unpushed commits, build
a review prompt, and run a one-shot ${name} code review with streaming
progress output.

Exits with an error if there is nothing to review.

## Agent instructions

Use a subagent to run this command — the review can take 1-3 minutes.
The command handles all prompt construction internally; just run it:

    Bash({ command: "${cmd} review", run_in_background: true })

GOLDEN RULE: EVERY finding the reviewer reports is YOUR responsibility.
Nothing in the diff is "pre-existing" or "not our commit". If it is in
the diff, it ships with your work. Investigate and fix ALL findings.
Never dismiss a finding. Never say "not actionable" or "good to note".
EOF
}
