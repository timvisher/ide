---
name: review
description: Run a skeptical code review via independent AI agents (`aishot review`). Use when you want a second opinion on your own work — uncommitted changes, a branch, or specific files.
user-invocable: true
---

# Code review

## When to use
- You want an independent review of code you just wrote or modified.
- The user asks you to review yourself or get a second opinion.
- Before committing or creating a PR, to catch issues you might have missed.

## How it works

Run `aishot review` in a subagent. It launches multiple independent AI
reviewers in parallel (Claude + Codex by default), collects their
findings, and synthesizes them into a unified report via claudeshot.

## Effort levels

The user can influence how many reviewers run. Map their intent to the
`--with=` flag:

| User says                              | Command                                      |
|----------------------------------------|----------------------------------------------|
| "review" (default)                     | `aishot review` (claude + codex)             |
| "quick review", "just claude"          | `aishot review --with=claude`                |
| "codex review", "review with codex"    | `aishot review --with=codex`                 |
| "gemini review"                        | `aishot review --with=gemini`                |
| "max effort", "thorough", "all"        | `aishot review --with=claude,codex,gemini`   |

## Workflow

### 1) Run the review

Use a subagent with a background Bash call — the full cycle (parallel
reviews + synthesis) can take 3-5 minutes:

```
Agent({
  description: "AI code review",
  prompt: "Run aishot review in the background and report the results.\n\nBash({ command: \"aishot review\", run_in_background: true })"
})
```

Adjust `--with=` based on user intent per the effort table above.

### 2) Present findings

**EVERY finding from the review is YOUR responsibility.** Do NOT dismiss,
filter, or deprioritize findings because they came from "other commits",
"pre-existing code", or code you didn't write in this session. Nothing
in the diff is pre-existing — if it's in the diff, it ships with your
work. Investigate and fix it. Never say "not our commits" or "good to
note but not actionable". ALL findings are actionable.

Read the synthesized output and present the findings to the user:
- **High confidence** findings (multiple reviewers agree) — fix these.
- **Worth investigating** findings (single reviewer) — assess and fix.
- **Disagreements** — give your own assessment.

If the review finds issues you agree with, fix them — don't just offer.
If the review is wrong about something, explain why to the user.

**pr.md**: If `pr.md` is in the diff and the review flags inaccuracies
in it, you MUST update `pr.md` to reflect all feedback before
considering the review complete.

## See also

- `aishot --help` — full usage for the aishot orchestrator
- `claudeshot --help` / `codexshot --help` — individual reviewer commands
