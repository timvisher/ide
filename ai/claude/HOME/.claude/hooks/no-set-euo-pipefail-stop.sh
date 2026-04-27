#!/usr/bin/env bash
# Stop hook: warn if Claude's last assistant turn mentioned `set -euo pipefail`.
# Reads the transcript path from stdin JSON, scans the last assistant message
# for the forbidden phrase, and emits hookSpecificOutput.additionalContext if
# matched. Silent passthrough on no match.

INPUT=$(cat)
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
[ -z "$TP" ] && exit 0
[ ! -r "$TP" ] && exit 0

TEXT=$(tail -n 200 "$TP" 2>/dev/null \
  | jq -rs 'map(select(.type=="assistant")) | .[-1] // {} | (.message.content // []) | .[]? | select(.type=="text") | .text // ""' \
  2>/dev/null)

printf '%s' "$TEXT" | grep -q 'set -euo pipefail' || exit 0

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: "REMINDER: you just mentioned `set -euo pipefail`. Before doing it again, read ~/.agents/languages/bash.md — this codebase has specific conventions about bash error handling."
  }
}'
