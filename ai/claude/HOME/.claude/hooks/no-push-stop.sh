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

    # Announce-then-defer. The bare "haven't pushed" / "pushed
    # somewhere" forms false-positive on array.push prose ("haven't
    # pushed it to the array", "pushed somewhere earlier in the
    # function"), so anchor each variant on git-vocabulary context
    # within a short window.
    "haven'?t pushed[^.\n]{0,80}(commit|branch|remote|origin|upstream|wip|HEAD|@\{u\}|the change|to (origin|main|master))"
    "haven'?t pushed[[:space:]]*[—.\,;:]"
    'pushed (it|this|them|the (commit|change|branch))[^.\n]{0,80}(somewhere|to (origin|main|master|upstream|remote))'
    'rebased/pushed'
    'rebased and pushed'
    'rebased or pushed'
    'pushed if you want'
    'if you want[^.\n]{0,40}(it|this|them|the.{0,15})[[:space:]]+pushed'
    'want (this|it|them).{0,20}push(ed)?[[:space:]]*(to|$|[.,;:!?])'

    # Plan/list items: "3. Push", "- Push to remote", "* Push.".
    # Caught the bare "3. Push" variant that earlier conversational
    # patterns missed.
    '^[[:space:]]*[0-9]+\.[[:space:]]*push'
    '^[[:space:]]*[-*][[:space:]]+push'

    # Standalone imperative on its own line.
    '^[[:space:]]*push[.,:![:space:]]*$'

    # Imperative-self sequencing: "Then push", "Now push", "Finally, push", "Next, push".
    '^[[:space:]]*(then|now|finally|next)[,.[:space:]]+(.{0,40}[[:space:]]+)?push'

    # Numbered/lettered "Step N: ... push" / "Stage N: ... push" prose.
    '(step|stage)[[:space:]]+[0-9]+[[:space:]]*[:.][[:space:]]*.{0,60}push'
)

# Join patterns into a single ERE alternation. Patterns themselves
# already use `|` for sub-alternation (e.g. `(then|now|finally)`); the
# join just adds another level of OR. None of our patterns include a
# literal `|` that would need escaping — if you add one, escape it as
# `\|` to keep the join unambiguous.
REGEX=$(IFS='|'; echo "${PATTERNS[*]}")

if printf '%s' "$TEXT" | grep -iEq "$REGEX"
then
    REASON='STOP HOOK VIOLATION: Agents must NEVER push to remotes. Re-read ~/git/ide/bash/bin/git (push guard, ~line 1357) for the canonical aictl_die: code "git_push_blocked", message "Agents must NEVER push to remotes. This is a non-negotiable safety rule.", suggestion "Ask the human to run git push". Do not ask, propose, condition on, or announce push. Just stop.'
    jq -nc --arg r "$REASON" '{decision: "block", reason: $r}'
    exit 0
fi

exit 0
