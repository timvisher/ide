---
name: make-skill
description: Create new agent skills, place them in the correct repo, and install them via timvisher_agents_install.
---

# Creating agent skills

## When to use
- Creating a new skill from scratch.
- Deciding whether a skill belongs in the general IDE repo or the
  DataDog extensions repo.
- Installing a newly created skill so it is available to Claude Code,
  Codex, and other agents.

## Skill anatomy

Every skill lives in its own directory with this structure:

```
<skill-name>/
├── SKILL.md              # required — frontmatter + documentation
├── agents/
│   └── openai.yaml       # required — agent interface config
├── references/
│   └── <name>.md         # optional — detailed reference material
└── scripts/              # optional — helper scripts
```

### SKILL.md

YAML frontmatter followed by markdown:

```markdown
---
name: <skill-name>
description: One-line description shown in skill lists.
---

# Skill title

## When to use
- Circumstance 1
- Circumstance 2

## Workflow
Step-by-step instructions.

## References
- See references/<name>.md for details.
```

Optional frontmatter fields:
- `disable-model-invocation: true` — only users can invoke (slash command only)
- `user-invocable: false` — only the model can invoke (no slash command)
- `allowed-tools: Read, Grep, Glob` — restrict available tools
- `context: fork` — run in isolated subagent
- `agent: Explore` — subagent type

### agents/openai.yaml

```yaml
interface:
  display_name: "Human Readable Name"
  short_description: "Brief description for UI"
```

Add `default_prompt:` only when the skill benefits from a pre-filled
prompt (e.g. skills that always start the same way).

### references/

Use a references directory when the skill needs extensive command
listings, cheat sheets, or detailed documentation that would bloat
SKILL.md. Keep SKILL.md focused on workflow; put reference material
here.

## Choosing the correct repo

There are two source repositories for skills:

| Repo | Path | Content |
|------|------|---------|
| General IDE | `~/git/ide/ai/HOME/.agents/skills/` | Generic skills usable anywhere |
| DataDog extensions | `~/.config/timvisher/ide/ai/HOME/.agents/skills/` | DataDog-specific skills |

### Decision criteria

Place the skill in **DataDog extensions** if ANY of these apply:
- References DataDog-internal tools (ddcspctl, cfctl, sdpctl, etc.)
- References DataDog infrastructure (AppGate, IPAAM, etc.)
- References DataDog-specific services or APIs
- Uses DataDog SSO, accounts, or auth patterns
- Would not make sense outside a DataDog environment

Place the skill in the **general IDE repo** for everything else:
- Git workflows, editor tooling, shell utilities
- Open-source tool integrations (1Password, GitHub, Terraform concepts)
- Personal workflow patterns (beads, worktrees, daily review coordination)
- Skills that reference DataDog tools only incidentally (e.g. a
  terraform skill that happens to mention cfctl goes in DataDog
  extensions because cfctl is DataDog-specific)

## Creating the skill

1. **Pick the repo** using the criteria above.

2. **Create the directory**:
   ```bash
   skill_dir="<repo-path>/<skill-name>"
   mkdir -p "${skill_dir}/agents"
   ```

3. **Write SKILL.md** with frontmatter, "When to use", and "Workflow"
   sections.

4. **Write agents/openai.yaml** with display_name and
   short_description.

5. **Add references/** if the skill needs detailed reference material.

## Installing the skill

After creating the skill files, run the installer to symlink it into
`~/.agents/skills/` and propagate to `~/.claude/skills/` and
`~/.codex/skills/`:

```bash
timvisher_agents_install \
  ~/git/ide/ai/HOME \
  ~/.config/timvisher/ide/ai/HOME
```

This is idempotent — safe to re-run at any time. It will:
- Symlink each skill directory from both repos into `~/.agents/skills/`
- Symlink `~/.claude/skills` → `~/.agents/skills`
- Symlink per-skill entries into `~/.codex/skills/`
- Error (not overwrite) on name conflicts

After installation the skill is immediately available — no restart
needed.

## Naming conventions

- Use kebab-case for skill directory names (e.g. `dev-integration-branch`)
- The `name:` in SKILL.md frontmatter must match the directory name
- `display_name` in openai.yaml can use title case with spaces

## Style guidelines

- Keep SKILL.md under ~100 lines; push details to references/
- Use imperative tone ("Run this command", not "You should run")
- Include concrete examples and code blocks
- Reference other skills by name when workflows overlap (e.g.
  "Use the `worktree` skill to create the worktree")
