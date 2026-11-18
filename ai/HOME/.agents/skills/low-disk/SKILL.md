---
name: low-disk
description: Measure and reclaim disk space through pluggable consumers. Use when the disk is full or nearly full, when a build or tool fails with "no space left on device", or when asked to free up disk space.
---

# Low disk

## When to use
- The disk is full or nearly full.
- A command failed with "no space left on device".
- The user asks to free up or reclaim disk space.

## Workflow

1. See what is using the disk:
   ```bash
   ~/.agents/skills/low-disk/scripts/low-disk measure
   ```
   It prints one JSON object with each plugin's targets and their `bytes`.
2. Show the user the biggest targets and their sizes, and get an OK before
   reclaiming anything.
3. Reclaim the approved targets:
   ```bash
   ~/.agents/skills/low-disk/scripts/low-disk reclaim <plugin>:<target>...
   ```
   Each plugin decides what is safe and reports what it did or refused.

`low-disk activity` shows which worktrees have a tmux client attached
(never reclaim from those) or are protected by dev_ci. The bundled
plugins only measure; their `reclaim` refuses and says why.

## References
- See references/protocol.md for the plugin contract.
