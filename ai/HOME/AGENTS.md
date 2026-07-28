# The most important thing

**NEVER use EnterPlanMode.** You should only ever use beads for planning.
If you need to plan, use `bd` — never enter plan mode.

When starting a session, read the Beads and Topics section below and use the `beads` skill if bd is enabled.

## Beads and Topics (Required)

- **bd (beads)** is used for issue tracking in all git repositories.
  If you are not in a git repo, do not use bd.
- Beads is "live" in a worktree when the repo root contains a `.beads`
  directory or `.timvisher_bd_topics` directory. `.beads` is always a
  directory — never read it as a file or inspect its contents.
- Before doing any work, check if beads is live. If it is **not** live,
  list topics and offer to set one:
  ```bash
  timvisher_bd_topics ls
  timvisher_bd_topics set <topic>
  ```
- Run `bd prime` for workflow context, or install hooks with
  `bd hooks install`.
- For the full workflow and session completion rules, use the `beads` skill.

## General Configuration

- **System Date Command**: This macOS system has GNU `date` installed (via
  Homebrew at `/opt/homebrew/bin/date`). ALWAYS use GNU date syntax (e.g.,
  `date -d '2025-11-04 00:00:00'` or `date -d @1730678400`) rather than BSD
  date syntax (e.g., `date -j -f`). All date command examples in this file
  use GNU date syntax and will work correctly on this system.
- Read-only commands should always be considered safe. Examples like `git
  rev-parse|log`, `find`, `ls`, etc.
- When providing commands for me to copy/paste: _*Always*_ be sure that
  they are properly escaped and line-wrapped. Pay very close attention to
  line wrappings that break apart words or commands that need to be broken
  across multiple lines that require `\` escaping of newline breaks.
- Commands that require user interaction (like `terraform apply` which
  needs approval, or `terraform init -migrate-state` which prompts for
  confirmation) should be written to `"$(git rev-parse
  --show-toplevel)"/y` file in the repo root for me to run
- Non-interactive commands (like `git commit`, `terraform plan`, etc.)
  can be run directly by Agent
- `op` (1Password CLI) is non-interactive for this policy; do not route
  it through `y` scripts or ask me to run it
- All commands (whether run by Agent or written to `y`) should anchor
  themselves with `$(git rev-parse --show-toplevel)` so that it doesn't
  matter where they're run from in the repo
- **Temporary script files**: Shim scripts and other temporary helper
  scripts should always be prefixed with `x.`, `y.`, or `z.` according to
  gitignore rules
  - These prefixes ensure scripts are automatically ignored by git
  - Example: `x.backup-gov-6.3.sh`, `y.restore-controller.sh`,
    `z.cleanup.sh`
  - Use `x.` for general helper scripts
  - Use `y.` for interactive scripts (user needs to run)
  - Use `z.` for cleanup or one-time scripts
- **Searching in Git Repositories**: _*NEVER*_ use `find` with `-exec grep`
  or `find` with `xargs git grep` to search for content in a git repository.
  This is inefficient and ignores git metadata.
    - Bad example: `find . -name "*.tf" -type f -exec grep -l "pattern" {} \;`
    - Bad example: `find . -type f -name "main.tf" | xargs git grep -l "profile.*="`
    - Use `git grep` with pathspecs instead: `git grep "pattern" -- '*.tf'`
    - Or for specific filenames: `git grep "profile.*=" -- '**/main.tf'`
    - Or use `ag` (the silver searcher): `ag "pattern" --tf`
    - Or use `rg` (ripgrep)
    - `git grep`, `ag`, and `rg` respect `.gitignore`, are faster, and provide
      better context
- **Atomic commits**: When committing, always split unrelated changes into
  separate commits. Never ask — just do it. Each commit should contain one
  logical change.
- **Prefer less-than family of comparison operators**: In all languages,
  always use `<` and `<=` (or language equivalents) rather than `>` and `>=`
  for consistency and readability
    - Good: `if (( 1 < ${#array[@]} ))` (Bash)
    - Avoid: `if (( ${#array[@]} > 1 ))` (Bash)
    - Good: `if (( count <= threshold ))` (Bash)
    - Avoid: `if (( threshold >= count ))` (Bash)
    - Good: `if count < threshold:` (Python)
    - Avoid: `if threshold > count:` (Python)

## Core Development Workflow

- You are _*NEVER*_ done until you've run lint and test steps.
- If possible, run focused lints and tests while iterating, but before you say
  you're done always run the full lint and tests for the component you're
  working on.
- In monorepos, "full tests" means the full test suite for the project you're
  working on, not every test in the repo.
- There is probably more specific guidance for a particular language or
  technology in the respective skill docs.
- For doc updates, the lint step is a spell check; run it before saying you're
  done.
- For doc-only changes with no meaningful tests, state that explicitly.
- _*NEVER*_ add an explanatory comment on your own initiative — a comment that
  explains _why_ a change was made, narrates your reasoning or investigation,
  cites tickets/PRs/runbooks, or restates what the code plainly does. That
  context is the job of the commit message and PR description. Add such a
  comment only when the human explicitly asks for one, or judges a specific one
  worth keeping.
- This _*overrides*_ "match the surrounding comment density." Existing
  explanatory comments in a file do _*NOT*_ license new ones — do not imitate
  them. Absent a human request, write zero comments.
- Before you say you are done, re-read your diff and delete every explanatory
  comment you added that the human did not ask for. Treat a leftover one as a
  failing lint: you are not done until it is gone.

## Documentation Index

When working with specific languages or tools, read these files for
detailed instructions:

### Languages

- `~/.agents/languages/applescript.md` -
  AppleScript encoding, git diff handling
- `~/.agents/languages/bash.md` - Quote usage,
  then/do formatting, logging patterns
- `~/.agents/languages/terraform.md` - Workflow
  scripts, tagging, migrations, modules
- `~/.agents/languages/org-mode.md` - Large file
  navigation tools, formatting conventions
- `~/.agents/languages/emacs-lisp.md` - ERT
  testing patterns

### Repository Organization

#### IDE Configuration Repositories

- Two separate IDE configuration git repositories:
  - `~/git/ide/` - General IDE configuration repo
    (`timvisher-ide.git`)
  - `~/.config/timvisher/ide/` - DataDog system extensions IDE repo
    (`timvisher-ide-datadog-system-extensions.git`)
- Agent runtime configuration is at `~/.config/timvisher/ide/ai/`
- The actual `~/AGENTS.md` file is a symlink to
  `~/git/ide/ai/HOME/AGENTS.md`

#### General Repository Layout

- **Creating worktrees**: _*NEVER*_ use raw `git worktree add`. Always
  use the `worktree` skill (`ntmux3 -d` for agent/scripted use).
- Git repositories are managed as worktrees under `~/git/` following a
  hierarchical structure:
  `~/git/<org or user>/<repo>/<branch-part>/<branch-part>/<branch-part-N>/`
- Bare repo caches live at
  `~/.cache/timvisher_git_worktrees/repo_trunks/<org>/<repo>/`
- Examples:
  - `~/git/DataDog/appgate/timvisher/scratch/_trunk_/`
  - `~/git/DataDog/cloud-inventory/timvisher/scratch/_trunk_/`
  - `~/git/DataDog/dd-source/main/`
- The branch path components reflect the git branch name structure
- When working with multiple related repos, they often share the same
  branch path structure (e.g., `timvisher/scratch/_trunk_` across
  different org repos)

## Git Commit & Push Policy (overrides the Beads profile)

The Beads Integration block below ships a "Conservative (default)"
profile that forbids commits, pushes, and Dolt sync unless explicitly
asked. **I explicitly reject that profile.** It does not govern my
repositories — it is auto-generated by `bd hooks install`, and this
section lives outside the `BEGIN`/`END BEADS INTEGRATION` markers on
purpose so regeneration cannot clobber it. Where this section and the
Beads block disagree, this section wins.

Follow my usual git rules instead:

- **Commit proactively without asking.** Make atomic commits as work
  reaches a coherent state; split unrelated changes into separate
  commits (see "Atomic commits" above). Never ask first — just do it.
- **Finish by pushing.** A unit of work is not done until it is
  committed *and* pushed. Run the session-completion push workflow
  rather than handing off with commits stranded locally.
- Still ask first only for destructive or history-rewriting remote
  operations (force-push, amending or rebasing already-published
  commits) and anything my other standing rules already gate.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
