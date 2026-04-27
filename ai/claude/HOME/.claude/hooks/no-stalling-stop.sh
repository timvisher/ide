#!/usr/bin/env bash
# Stop hook: catch ownership-dodging, session-length self-stopping,
# and permission-seeking patterns in the agent's last assistant turn.
# When matched, output `decision: "block"` with the rule as `reason` —
# the harness suppresses the violating turn and forces the agent to
# continue with the rule injected as its next instruction.
#
# Inspired by github.com/benvanik/ee00bd1b6c9154d6545c63e06a317080;
# pattern set tailored to Tim's actual workflow (push prohibited for
# agents; commits OK without asking; explicit gate-checks like
# "should I push?" are disallowed because Tim cleans up at session end).

INPUT=$(cat)

# Infinite-loop guard. The harness sets stop_hook_active=true on the
# second+ stop in the same turn; bail so the original block survives.
if [[ $(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false') == "true" ]]
then
    exit 0
fi

TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
[ -z "$TP" ] && exit 0
[ ! -r "$TP" ] && exit 0

TEXT=$(tail -n 200 "$TP" 2>/dev/null \
  | jq -rs 'map(select(.type=="assistant")) | .[-1] // {} | (.message.content // []) | .[]? | select(.type=="text") | .text // ""' \
  2>/dev/null)

[ -z "$TEXT" ] && exit 0

# Each violation: "grep_pattern|reason"
# Patterns are checked case-insensitively against the full assistant
# turn text. First match wins; ordered by severity / specificity.
VIOLATIONS=(
    # --- Ownership dodging (mirror of aishot review GOLDEN RULE) ---
    'pre-existing|NOTHING IS PRE-EXISTING. You own every change in the `@{u}...` diff. If something fails, your work caused it. Investigate and fix.'
    'not from my changes|NOTHING IS PRE-EXISTING. You own every change in the `@{u}...` diff. Investigate and fix.'
    'not my change|NOTHING IS PRE-EXISTING. You own every change in the `@{u}...` diff. Investigate and fix.'
    'not caused by my|NOTHING IS PRE-EXISTING. You own every change in the `@{u}...` diff. Investigate and fix.'
    'not introduced by my|NOTHING IS PRE-EXISTING. You own every change in the `@{u}...` diff. Investigate and fix.'
    'unrelated to my changes|NOTHING IS PRE-EXISTING. Nothing is unrelated. Investigate and fix.'
    'before my changes|NOTHING IS PRE-EXISTING. There is no "before your changes" — the `@{u}...` diff is yours.'
    'prior to my changes|NOTHING IS PRE-EXISTING. There is no "prior to your changes" — the `@{u}...` diff is yours.'
    'already existed before|NOTHING IS PRE-EXISTING. If you found it broken, fix it or explain exactly what is wrong.'
    'an existing issue|NOTHING IS PRE-EXISTING. Investigate and fix.'
    'existing bug|NOTHING IS PRE-EXISTING. Investigate and fix.'

    # --- Push proposals: handled by the dedicated no-push-stop.sh hook,
    #     which references bash/bin/git's push guard for the canonical
    #     git_push_blocked aictl_die message. Keep this file focused on
    #     the other self-correction patterns.

    # --- Commit-permission asks (just commit and continue) ---
    'should i commit|Just commit. Human will help clean up …'
    'shall i commit|Just commit. Human will help clean up …'
    'want me to commit|Just commit. Human will help clean up …'
    'would you like me to commit|Just commit. Human will help clean up …'
    'ready to commit|Just commit. Human will help clean up …'
    'commit\?|Just commit. Human will help clean up …'
    'commit, or|Just commit. Human will help clean up …'
    'want it committed|Just commit. Human will help clean up …'
    'want them committed|Just commit. Human will help clean up …'
    'want this committed|Just commit. Human will help clean up …'

    # --- Session-length self-stopping (sessions are unlimited) ---
    'good place to stop|Sessions are unlimited. Continue if the task is not done.'
    'good stopping point|Sessions are unlimited. Continue if the task is not done.'
    'good checkpoint given|Sessions are unlimited. Continue if the task is not done.'
    'natural stopping|Sessions are unlimited. Continue if the task is not done.'
    'logical stopping|Sessions are unlimited. Continue if the task is not done.'
    'getting long|Sessions are unlimited. Continue working.'
    'lengthy session|Sessions are unlimited. Continue working.'
    'session length|Sessions are unlimited. Continue working.'
    'session depth|Sessions are unlimited. Continue working.'
    'session has been long|Sessions are unlimited. Continue working.'
    'this session has gotten long|Sessions are unlimited. You are a machine. Continue working.'
    'given the length of this|Sessions are unlimited. Continue working.'

    # --- Permission-seeking on continuation (just continue) ---
    'should i continue|Do not ask. If the task is not done, continue.'
    'shall i continue|Do not ask. Continue working until the task is complete.'
    'would you like me to continue|Do not ask. Continue.'
    'would you like to continue|Do not ask. Continue.'
    'want me to keep going|Do not ask. Keep going.'
    'want me to continue|Do not ask. Continue.'
    'should i keep going|Do not ask. Keep going.'
)

for entry in "${VIOLATIONS[@]}"
do
    pattern="${entry%%|*}"
    reason="${entry#*|}"
    if printf '%s' "$TEXT" | grep -iEq "$pattern"
    then
        jq -nc --arg r "STOP HOOK VIOLATION: $reason" '{decision: "block", reason: $r}'
        exit 0
    fi
done

exit 0
