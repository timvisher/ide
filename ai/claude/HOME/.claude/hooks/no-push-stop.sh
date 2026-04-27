#!/usr/bin/env bash
# Stop hook: rebut any text from the agent suggesting it can, will, or
# might `git push`, with a pointer to bash/bin/git's push guard for the
# canonical aictl_die error message.
#
# The wrapper at ~/git/ide/bash/bin/git aictl_die's any non-bd-dolt
# push with code git_push_blocked. This hook intercepts the *textual*
# suggestions before they get acted on (or before the user has to read
# them), and forces the agent to re-read the wrapper before proposing
# push again.

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

# Patterns suggesting the agent thinks it can push (case-insensitive,
# extended regex). Covers asking, declarative, conditional, and
# announce-then-defer phrasings. Order doesn't matter — first match wins.
PATTERNS=(
    # Asking permission
    'should i push'
    'shall i push'
    'want me to push'
    'would you like me to push'
    'ready to push'
    'push\?'
    'push, or'
    'push or hold'

    # Declarative / claim of permission
    "i'?ll push"
    "i'?m pushing"
    'i can push'
    "i'?m allowed to push"
    "i'?ve been authorized to push"
    'permission to push'
    'let me push'

    # Announce-then-defer ("haven't pushed", "let me know if you want pushed", etc.)
    "haven'?t pushed"
    'pushed somewhere'
    'rebased/pushed'
    'rebased and pushed'
    'rebased or pushed'
    'pushed if you want'
    'if you want.{0,30}push'
    'want this push'
    'want it push'
    'want them push'
)

REGEX=$(IFS='|'; echo "${PATTERNS[*]}")

if printf '%s' "$TEXT" | grep -iEq "$REGEX"
then
    REASON='STOP HOOK VIOLATION: Agents must NEVER push to remotes. Re-read ~/git/ide/bash/bin/git (push guard, ~line 1357) for the canonical aictl_die: code "git_push_blocked", message "Agents must NEVER push to remotes. This is a non-negotiable safety rule.", suggestion "Ask the human to run git push". Do not ask, propose, condition on, or announce push. Just stop.'
    jq -nc --arg r "$REASON" '{decision: "block", reason: $r}'
    exit 0
fi

exit 0
