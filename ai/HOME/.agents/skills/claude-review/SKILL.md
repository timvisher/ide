---
name: claude-review
description: Run a skeptical code review via Claude (`claudeshot review`). Use when you want an independent second opinion from Claude on your own work — uncommitted changes, a branch, or specific files.
user-invocable: true
---

# Claude review

## When to use
- You want an independent review of code you just wrote or modified.
- The user asks you to review yourself or get a second opinion.
- Before committing or creating a PR, to catch issues you might have missed.
- You specifically want to use Claude (Anthropic) as the reviewer.

## How it works

Run `claudeshot review` in a subagent. The command automatically detects
uncommitted changes and/or unpushed commits, builds the review prompt,
and runs a one-shot Claude review with streaming progress output.

## Workflow

### 1) Run the review

Use a subagent with a background Bash call — the review can take
1-3 minutes:

```
Agent({
  description: "Claude code review",
  prompt: "Run claudeshot review in the background and report the results.\n\nBash({ command: \"claudeshot review\", run_in_background: true })"
})
```

### 2) Present findings

**EVERY finding from the review is YOUR responsibility.** Do NOT dismiss,
filter, or deprioritize findings because they came from "other commits",
"pre-existing code", or code you didn't write in this session. Nothing
in the diff is pre-existing — if it's in the diff, it ships with your
work. Investigate and fix it. Never say "not our commits" or "good to
note but not actionable". ALL findings are actionable.

Read the output and present the findings to the user. Summarize the key
points and highlight anything you agree or disagree with based on your
own understanding of the code.

If the review finds issues you agree with, fix them — don't just offer.
If the review is wrong about something, explain why to the user.

## See also

- `codexshot review` — same workflow using Codex instead of Claude
- `claudeshot --help` — full usage for the claudeshot command
