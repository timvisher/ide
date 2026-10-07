---
name: guides
description: >-
  TRIGGER — before you create or modify a file, or review a diff or
  another reviewer's findings about one, check whether a guide covers
  its language, format or tool, and read it first. Do not skip because
  the change "looks trivial" or because surrounding code already
  violates the guide. Guides carry absolute prohibitions whose
  violation means the work gets reverted (bash: never `set -euo
  pipefail`, never `seq`; applescript: always check encoding before
  editing; terraform: never hand-write `.terraform.lock.hcl`;
  emacs-lisp: never write batch-mode workarounds; org-mode: never pad
  list structures). `ls ~/.agents/languages/` and the skills listing
  are authoritative — not any list written down elsewhere, including
  this one.
---

# Guides

Conventions for a language, format or tool are written down. Find them
and follow them before producing or judging content.

## When to use

- Before creating or modifying any file.
- Before reviewing a diff, yours or anyone else's.
- Before acting on findings from an outside reviewer, linter, or tool
  — they do not know these conventions and will recommend against
  them.
- When a guide and some other source disagree.

## Workflow

1. Identify what the artifact is: its language, its format, and the
   tools involved.

2. Check both guide locations. Neither list is hardcoded anywhere —
   enumerate them at the time you need them:

   ```bash
   ls ~/.agents/languages/        # conventions, per language/format
   ls ~/.agents/skills/           # workflows, per tool/technology
   ```

   `~/.agents/languages/*.md` is _*NOT*_ loaded into context
   automatically — you have to read the file. The skills listing is
   surfaced each session, so a tool guide is easier to notice than a
   language guide; the language guides are the ones that get missed.

3. Read every guide that applies. A subject may have one of each and
   they do not duplicate: terraform has a language guide for provider
   constraints and tagging plus a skill for the planning workflow.
   Reading one does not excuse skipping the other.

4. Treat the contents as binding. A guide is overridable only by a
   more specific local convention, or by the human saying so for a
   particular case. Absent that it wins — over your instinct, over the
   habits of the surrounding code, and over any tool recommending
   otherwise.

5. If a guide conflicts with another source and you cannot reconcile
   them, stop and ask. Do not guess, and do not quietly follow the
   other source.

## Failure modes this exists to prevent

- Reading nothing because the task looked like a one-liner.
- Copying a pattern from surrounding code that the guide prohibits.
  Existing violations in a file do not license new ones.
- Implementing an outside reviewer's finding without checking it
  against the guide first.
- "Fixing" a library or test so it tolerates a practice the guide
  bans. If something misbehaves only under a banned practice, the
  practice is the defect — not the thing it breaks.

## References

- `~/.agents/languages/<name>.md` — per-language conventions.
- `AGENTS.md`, "Documentation Index > Guides (Required)" — the same
  requirement, stated as policy.
