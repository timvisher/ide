#!/usr/bin/env bash
# PreToolUse hook on Edit|Write|NotebookEdit: serialize mutating tool
# calls across multiple Claude sessions sharing one worktree.
#
# Model: lazy-acquire, eager-release. The first session to attempt a
# mutation in a worktree takes the lock; further mutations from the
# same session_id are reentrant. Other sessions' mutations are denied
# (with a reason naming the holder) but their reads/thinking are
# unrestricted because this hook only fires on the file-write tools.
#
# Anchor: the worktree containing the *target file* of the tool call,
# not the agent's cwd. A session whose cwd is worktree X but writes a
# file in worktree Y must contend with other Y-resident writers, not
# X-resident ones. cwd-anchoring would have left Y unprotected.
#
# Lock dir layout (per worktree):
#   ~/.claude/locks/<slug>/                   parent dir, mkdir -p safe
#   ~/.claude/locks/<slug>/active/            sentinel — kernel-atomic
#   ~/.claude/locks/<slug>/active/owner.json  {session_id, transcript_path, started_at}
#
# `slug` is the worktree root path with `/` replaced by `-`, matching
# how Claude itself encodes project dirs under ~/.claude/projects/.
#
# Stale-owner reclaim: liveness is derived from the holder's transcript
# file mtime — that file is Claude's own record of session activity,
# so we never have to manage PIDs (per ~/.agents/languages/bash.md).
# If the transcript is missing or older than STALE_SECONDS, rm -rf the
# active/ dir and retry. mkdir atomicity guarantees only one reclaimer
# wins; the loser observes the new owner on its next iteration.

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

[[ -n $SESSION_ID && -n $TRANSCRIPT_PATH ]] || exit 0

case $TOOL_NAME in
    Edit|Write)
        TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
        ;;
    NotebookEdit)
        TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.notebook_path // empty')
        ;;
    *)
        # Hook fired on an unmatched tool — nothing to lock.
        exit 0
        ;;
esac

# Without a target, no shared worktree is at risk.
[[ -n $TARGET ]] || exit 0

# Resolve the worktree from the target's parent dir. New-file writes
# point at not-yet-existing paths, so anchor on dirname rather than
# the path itself. Files outside any git repo no-op (no shared-worktree
# coordination problem applies).
TARGET_DIR=$(dirname -- "$TARGET")
WORKTREE=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0

SLUG=${WORKTREE//\//-}
LOCKDIR="${HOME}/.claude/locks/${SLUG}"
ACTIVE="${LOCKDIR}/active"
OWNER="${ACTIVE}/owner.json"

mkdir -p -- "$LOCKDIR" || exit 0

STALE_SECONDS=${CLAUDE_WORKTREE_LOCK_STALE_SECONDS:-900}

deny() {
    jq -nc --arg r "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
}

write_owner() {
    # `date -u +...Z` works on both GNU and BSD date; `-Iseconds` is
    # GNU-only and silently empty under BSD. The hook runs in whatever
    # PATH the harness provides, so we don't assume coreutils.
    jq -nc \
      --arg sid "$SESSION_ID" \
      --arg tp "$TRANSCRIPT_PATH" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{session_id: $sid, transcript_path: $tp, started_at: $ts}' \
      > "$OWNER"
}

# Bounded retry — each loop either acquires, observes a live owner, or
# reclaims a stale one. A live owner ends the loop with a deny.
for _ in {1..10}
do
    if mkdir -- "$ACTIVE" 2>/dev/null
    then
        write_owner
        exit 0
    fi

    # Contention. Read owner; if absent, the holder is mid-init — wait
    # briefly and retry.
    if [[ ! -r $OWNER ]]
    then
        sleep 0.1
        continue
    fi

    # Single jq read of owner.json — two separate invocations could
    # observe a reclaim mid-flight (TOCTOU between reads).
    { read -r OWNER_SID; read -r OWNER_TP; } < <(
        jq -r '.session_id // empty, .transcript_path // empty' "$OWNER" 2>/dev/null
    )

    if [[ -z $OWNER_SID ]]
    then
        # Malformed owner file — treat as stale.
        rm -rf -- "$ACTIVE"
        continue
    fi

    if [[ $OWNER_SID == "$SESSION_ID" ]]
    then
        exit 0
    fi

    NOW=$(date +%s)
    if [[ -n $OWNER_TP && -e $OWNER_TP ]]
    then
        # GNU stat (`-c %Y`) first, fall back to BSD stat (`-f %m`).
        # Validate numeric so a wrong-dialect mismatch can't poison the
        # arithmetic. On unknown-mtime, fail safe by treating the owner
        # as fresh: evicting a live owner causes corruption, while a
        # truly dead owner can be cleared manually.
        MTIME=$(stat -c %Y -- "$OWNER_TP" 2>/dev/null \
            || stat -f %m -- "$OWNER_TP" 2>/dev/null)
        if [[ $MTIME =~ ^[0-9]+$ ]]
        then
            AGE=$(( NOW - MTIME ))
        else
            AGE=0
        fi
    else
        AGE=$(( STALE_SECONDS + 1 ))
    fi

    if (( STALE_SECONDS < AGE ))
    then
        rm -rf -- "$ACTIVE"
        continue
    fi

    deny "Worktree '${WORKTREE}' is locked for mutation by Claude session ${OWNER_SID} (transcript mtime ${AGE}s old; threshold ${STALE_SECONDS}s). Read-only tools remain available. To take over, wait for the owning session to end or remove ${ACTIVE}."
done

deny "Worktree '${WORKTREE}' lock contention persisted for 10 retries; another session is initializing the lock. Try again."
