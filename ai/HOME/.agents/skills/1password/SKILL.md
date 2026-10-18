---
name: 1password
description: Use for 1Password vault/item operations via the op CLI, including creating and retrieving SSH keys, and BEFORE debugging any 1Password prompt or authorization problem — op hanging, "account is not signed in", "authorization timeout", repeated Touch ID dialogs, or git commit signing failing with "agent: client error: EOF" / "failed to write commit object". Records hard-won facts (op whoami is unreliable, timed-out probes leave dialogs up, batch op calls) that keep getting rediscovered.
---

# 1Password CLI (op)

## When to use
- Creating or retrieving 1Password items, especially SSH keys for infra work.
- Any `op` command hangs, fails on authorization, or prompts repeatedly.
- `git commit` or `git rebase` fails to sign through the 1Password SSH
  agent.
- Before deciding how to check whether a 1Password prompt will appear.

## Workflow
- Use `op` for all vault interactions.
- Quote item titles and field names when they include spaces.
- Vault names are case-sensitive.
- Supported SSH key types: ed25519, rsa, rsa2048, rsa3072, rsa4096.
- For anything that may prompt, read "Authorization prompts" and
  "Commit signing" in the reference first, and check the `away-status`
  skill before starting.

## References
- See references/1password.md for commands, authorization behavior and
  signing failures.
