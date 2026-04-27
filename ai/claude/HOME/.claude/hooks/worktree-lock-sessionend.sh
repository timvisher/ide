#!/usr/bin/env bash
# SessionEnd hook: release every worktree mutation lock owned by this
# session.
#
# Because worktree-lock-pretool.sh anchors on the target file's
# worktree (not cwd), a single session can hold locks across multiple
# worktrees concurrently. Scan every lockdir and release whichever
# owner.json matches our session_id; thinkers and non-owners no-op.
#
# Invariant from the pretool hook: only the session whose ID is inside
# owner.json may delete the lock. Thinkers (sessions that never
# mutated, so never acquired) must no-op — otherwise an unrelated
# session ending could yank a lock from the real holder.
#
# Crash/kill -9 cases bypass SessionEnd entirely; the pretool hook's
# transcript-mtime-based reclaim path covers those.

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

[[ -n $SESSION_ID ]] || exit 0

LOCKS_ROOT="${HOME}/.claude/locks"
[[ -d $LOCKS_ROOT ]] || exit 0

shopt -s nullglob
for owner in "$LOCKS_ROOT"/*/active/owner.json
do
    OWNER_SID=$(jq -r '.session_id // empty' "$owner" 2>/dev/null)
    if [[ $OWNER_SID == "$SESSION_ID" ]]
    then
        rm -rf -- "$(dirname -- "$owner")"
    fi
done
shopt -u nullglob

exit 0
