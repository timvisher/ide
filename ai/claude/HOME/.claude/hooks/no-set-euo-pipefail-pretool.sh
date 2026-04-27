#!/usr/bin/env bash
# PreToolUse hook on Write|Edit: block any diff that introduces
# `set -euo pipefail`. Reads the tool input JSON from stdin and emits a
# permissionDecision:"deny" if the new content contains the phrase.

INPUT=$(cat)
NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

case $NAME in
    Write) CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty') ;;
    Edit)  CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty') ;;
    *)     exit 0 ;;
esac

printf '%s' "$CONTENT" | grep -q 'set -euo pipefail' || exit 0

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Blocked: this edit/write contains `set -euo pipefail`. Read ~/.agents/languages/bash.md for the project bash conventions before adding it."
  }
}'
