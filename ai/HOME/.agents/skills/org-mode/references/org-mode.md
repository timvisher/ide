# Org Mode Helper Tools and Workflow

## Org Helper Tools
All tools are on `PATH` (installed via `~/bin/`).

1. **org-outline** — Show heading structure
   ```bash
   org-outline <file.org> [max-depth]
   ```
   - Shows hierarchical heading structure
   - Default depth is 3 levels
   - Use this first to understand file organization
   - Example: `org-outline todo.org 2`

2. **org-extract** — Extract specific sections
   ```bash
   org-extract <file.org> <heading-text>
   ```
   - Extracts a heading and its complete subtree
   - Use after identifying relevant sections with org-outline
   - Example: `org-extract projects.org "Network Migration"`

3. **org-todos** — List TODO items
   ```bash
   org-todos <file.org>
   ```
   - Shows all TODO/DONE/IN-PROGRESS/WAITING items with indentation
   - Useful for seeing action items without full context
   - Example: `org-todos todo.org`

4. **org-add-heading** — Add new headings
   ```bash
   org-add-heading <file.org> <heading-text> [parent-heading]
   ```
   - Adds a new heading to the file
   - If parent-heading is provided, adds as child of that heading
   - If no parent, adds as top-level heading at end
   - Example: `org-add-heading todo.org "New Task"`
   - Example: `org-add-heading todo.org "Subtask" "Parent Task"`

## Best Practices

1. **Always start with structure, not content**
   - Run `org-outline <file> [depth]` first
   - Show the outline to the user if uncertain about relevance
   - Ask the user which sections matter when unclear
   - Read full sections only after identifying relevant areas

2. **Extract focused sections**
   - Use `org-extract` to read specific sections instead of full files
   - This reduces context usage and improves accuracy
   - Verify you are reading the right section

3. **Use org-add-heading for updates**
   - Always use org-add-heading instead of manual editing when adding new headings
   - This ensures proper indentation and structure
   - Honors org-mode hierarchy automatically

4. **Respect file organization**
   - Org files are trees, not flat documents
   - Maintain heading hierarchy when making changes
   - Keep related content under appropriate parent headings

## Special Rules for todo.org
- Keep contents in chronological order (order of creation)
- Do not reorder headings arbitrarily
- Mark irrelevant items as DONE instead of deleting
- Move completed items to a Done section if one exists
- Archive old items by moving to subheadings, not by deletion

## Workflow for Large Files

```bash
# 1. Get overview
org-outline large-file.org 2

# 2. Ask user which sections are relevant

# 3. Extract and read only relevant sections
org-extract large-file.org "Relevant Section" | head -100

# 4. If adding content, use org-add-heading
org-add-heading large-file.org "New Heading" "Parent Section"
```

## When to Use Each Tool
- **org-outline**: Always use first when encountering a large org file
- **org-extract**: Use when you need to read specific sections
- **org-todos**: Use when you need to see just action items
- **org-add-heading**: Always use when adding new headings (never edit manually)
