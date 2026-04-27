#!/usr/bin/env bash
# Stop hook: when the assistant just processed the output of an
# `aishot review`, block dismissal phrasing per the GOLDEN RULE.
#
# `aishot review --help` says:
#   GOLDEN RULE: EVERY finding from the review is YOUR responsibility.
#   Nothing in the diff is "pre-existing" or "not our commit". If it
#   is in the diff, it ships with your work. Investigate and fix ALL
#   findings. Never dismiss a finding. Never say "not actionable" or
#   "good to note".
#
# That rule lives in the help text, which the agent reads once at
# kickoff. Five minutes later, when the synthesized report arrives,
# the rule is stale in context — and an agent can slip into "X is
# unrelated to this session's work" within seconds. This hook is the
# safety net.
#
# Scope: fires only when the most recent ~200 transcript lines
# include an `aishot review` Bash tool call. Otherwise the dismissal
# vocabulary is just normal English.

INPUT=$(cat)

# Infinite-loop guard: harness sets stop_hook_active=true on the
# second+ stop in the same turn; bail so the original block survives.
if [[ $(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false') == "true" ]]
then
    exit 0
fi

TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
[ -z "$TP" ] && exit 0
[ ! -r "$TP" ] && exit 0

# Was `aishot review` run anywhere in the recent transcript window?
RECENT_REVIEW=$(tail -n 200 "$TP" 2>/dev/null \
  | jq -rs '
    [.[] | select(.type=="assistant") | (.message.content // []) | .[]?
      | select(.type=="tool_use" and .name=="Bash"
               and ((.input.command // "") | test("aishot review")))]
    | length' \
  2>/dev/null)

[ -z "$RECENT_REVIEW" ] && exit 0
(( 0 < RECENT_REVIEW )) || exit 0

# Most recent assistant text content.
TEXT=$(tail -n 200 "$TP" 2>/dev/null \
  | jq -rs 'map(select(.type=="assistant")) | .[-1] // {} | (.message.content // []) | .[]? | select(.type=="text") | .text // ""' \
  2>/dev/null)

[ -z "$TEXT" ] && exit 0

# Dismissal patterns (case-insensitive ERE). Kept narrow to avoid
# false positives on legitimate uses of "scope", "unrelated", etc.
PATTERNS=(
    # Direct verdicts
    '\bnot actionable\b'
    '\bgood to note\b'
    "won'?t fix"
    '\bwontfix\b'

    # Scope-shrinking ("not my problem")
    '\bnot in scope\b'
    '\bout of scope\b'
    '\boutside (the )?scope\b'
    '\bnot my (work|problem|issue|bug)\b'
    '\bnot from this session\b'

    # "Pre-existing" carveouts the GOLDEN RULE forbids
    '\bpre-existing\b'
    '\bpre existing\b'
    '\bpreexisting\b'

    # "Unrelated to this/our/the {session,change,work,review,...}"
    '\b(unrelated|not pertinent|not relevant) to (this|that|our|the|the current|the present)( [a-z]+)? (session|change|commit|work|task|review|request|pr|diff|fix)'

    # Dismissal-by-deferral
    "\bdoesn'?t apply (here|to (this|that|our|the))"
    '\bn/?a for (this|that|our|the|the current|the present)\b'
)

REGEX=$(IFS='|'; echo "${PATTERNS[*]}")

if printf '%s' "$TEXT" | grep -iEq "$REGEX"
then
    REASON='STOP HOOK VIOLATION: aishot review GOLDEN RULE. EVERY finding in the synthesized report is YOUR responsibility — including findings about commits/files you did not touch in this session. Re-read the rule via `aishot review --help`. Address each finding directly: fix it, or file it as a beads issue with investigation notes (and reference the bd id in your reply). Do not dismiss with phrases like "not actionable", "out of scope", "pre-existing", "unrelated to this session", "good to note", or "won'\''t fix" — that is exactly the language the rule forbids.'
    jq -nc --arg r "$REASON" '{decision: "block", reason: $r}'
fi

exit 0
