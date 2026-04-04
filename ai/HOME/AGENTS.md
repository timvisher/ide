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
