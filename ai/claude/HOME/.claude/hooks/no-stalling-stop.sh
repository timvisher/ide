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
# Tab-delimited pattern|reason so patterns may use `|` for alternation.
# Format: $'<pattern>\t<reason>'
DODGE_REASON='NOTHING IS PRE-EXISTING. You own every change in the `@{u}...` diff. If something fails, your work caused it. Investigate and fix.'
VIOLATIONS=(
    # --- Ownership dodging (mirror of aishot review GOLDEN RULE) ---
    # Each pattern is anchored on dodging context. Bare phrases like
    # "the pre-existing API contract" or "an existing issue on GitHub"
    # are legitimate review prose; anchors require proximity to a
    # dismissal stance ("this is", "looks like") or a problem noun
    # ("issue", "bug", "failure", "breakage", "test").
    $'pre-existing[[:space:]]+(issue|bug|problem|failure|test|breakage|condition)\t'"$DODGE_REASON"
    $'(this is|that is|it.?s|looks like|appears|seems)[^.\\n]{0,40}pre-existing\t'"$DODGE_REASON"
    $'pre-existing,[[:space:]]+not (mine|from)\t'"$DODGE_REASON"
    $'not from my changes\t'"$DODGE_REASON"
    $'not my change\t'"$DODGE_REASON"
    $'not caused by my\t'"$DODGE_REASON"
    $'not introduced by my\t'"$DODGE_REASON"
    $'unrelated to my changes\t'"$DODGE_REASON"
    $'before my changes\t'"$DODGE_REASON"
    $'prior to my changes\t'"$DODGE_REASON"
    $'already existed before\t'"$DODGE_REASON"
    # "an existing issue" / "existing bug" alone are too broad — match
    # dismissal stance only.
    $'(this|that|it).{0,15} an existing (issue|bug|problem)\t'"$DODGE_REASON"
    $'(this|that|it).{0,15} existing (bug|issue|problem)[^a-z]\t'"$DODGE_REASON"

    # --- Push proposals: handled by the dedicated no-push-stop.sh hook,
    #     which references bash/bin/git's push guard for the canonical
    #     git_push_blocked aictl_die message. Keep this file focused on
    #     the other self-correction patterns.

    # --- Commit-permission asks (just commit and continue) ---
    $'should i commit\tJust commit. Human will help clean up …'
    $'shall i commit\tJust commit. Human will help clean up …'
    $'want me to commit\tJust commit. Human will help clean up …'
    $'would you like me to commit\tJust commit. Human will help clean up …'
    $'ready to commit\tJust commit. Human will help clean up …'
    # `commit?` and `commit, or` were too broad ("a typo in this commit?" /
    # "rebase the commit, or revert?" are legit). Anchor on a permission-
    # seeking sentence shape.
    $'(should|shall|can|may|do you want me to|would you like me to).{0,30}commit\\?\tJust commit. Human will help clean up …'
    $'(commit and|just commit|to commit), or\tJust commit. Human will help clean up …'
    $'want it committed\tJust commit. Human will help clean up …'
    $'want them committed\tJust commit. Human will help clean up …'
    $'want this committed\tJust commit. Human will help clean up …'

    # --- Session-length self-stopping (sessions are unlimited) ---
    $'good place to stop\tSessions are unlimited. Continue if the task is not done.'
    $'good stopping point\tSessions are unlimited. Continue if the task is not done.'
    $'good checkpoint given\tSessions are unlimited. Continue if the task is not done.'
    $'natural stopping\tSessions are unlimited. Continue if the task is not done.'
    $'logical stopping\tSessions are unlimited. Continue if the task is not done.'
    # "getting long" / "session length" alone false-positive on prose
    # like "this list is getting long". Anchor on session/turn context.
    $'(this|the|our)[[:space:]]+(session|turn|conversation|chat)[^.\\n]{0,40}getting (too )?long\tSessions are unlimited. Continue working.'
    $'lengthy session\tSessions are unlimited. Continue working.'
    $'session length\tSessions are unlimited. Continue working.'
    $'session depth\tSessions are unlimited. Continue working.'
    $'session has been long\tSessions are unlimited. Continue working.'
    $'this session has gotten long\tSessions are unlimited. You are a machine. Continue working.'
    $'given the length of this[[:space:]]+(session|conversation|turn)\tSessions are unlimited. Continue working.'

    # --- Permission-seeking on continuation (just continue) ---
    $'should i continue\tDo not ask. If the task is not done, continue.'
    $'shall i continue\tDo not ask. Continue working until the task is complete.'
    $'would you like me to continue\tDo not ask. Continue.'
    $'would you like to continue\tDo not ask. Continue.'
    $'want me to keep going\tDo not ask. Keep going.'
    $'want me to continue\tDo not ask. Continue.'
    $'should i keep going\tDo not ask. Keep going.'
)

for entry in "${VIOLATIONS[@]}"
do
    # Tab-delimited so patterns may freely use `|` for alternation.
    pattern="${entry%%$'\t'*}"
    reason="${entry#*$'\t'}"
    if printf '%s' "$TEXT" | grep -iEq "$pattern"
    then
        jq -nc --arg r "STOP HOOK VIOLATION: $reason" '{decision: "block", reason: $r}'
        exit 0
    fi
done

exit 0
