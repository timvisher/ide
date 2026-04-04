---
name: make-prompt
description: Research a problem and produce a self-contained agent prompt as a chat message. Never write prompts to repo files.
---

# Make Prompt

## When to use

- User asks you to "make a prompt", "write a prompt", or "create a prompt"
  for another agent, session, or tool.
- User wants a bug report, task description, or handoff document formatted
  as an agent-consumable prompt.

## Rules

1. **Output is a chat message, not a file.** Never write the prompt to a
   repo file (e.g. `history/`, README, markdown doc). Always send it
   directly as a message to the user.
2. **Clipboard on request.** After sending the prompt, offer to copy it to
   the user's clipboard. If they accept, use `pbcopy` (macOS).
3. **Self-contained.** The prompt must include all context another agent
   needs: problem statement, evidence, relevant code paths, file locations,
   and repro steps. The receiving agent has no access to the current
   conversation.
4. **Research first.** Read code, grep for patterns, check logs — gather
   all the evidence before composing the prompt. Don't guess.

## Workflow

1. Investigate the problem: read files, search code, check logs/output.
2. Compose a self-contained prompt with:
   - Problem statement
   - Evidence and root cause analysis
   - Relevant file paths and code references
   - Suggested fix approach (when known)
   - Repro steps
3. If the prompt is for a worktree agent and a beads topic is active,
   include a setup step to set the topic in the worktree:
   `timvisher_bd_topics set <topic>` — worktrees under different bare
   repo trunks won't share the same `.beads/redirect`, so the agent
   needs to explicitly set the topic to access the right bead database.
4. Send the prompt as a chat message (in a fenced code block for easy
   copying).
5. Ask: "Want me to copy this to your clipboard?"
6. If yes: `echo '<prompt>' | pbcopy`
