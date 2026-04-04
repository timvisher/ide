---
name: 1password
description: Use for 1Password vault/item operations via the op CLI, including creating and retrieving SSH keys.
---

# 1Password CLI (op)

## When to use
- Creating or retrieving 1Password items, especially SSH keys for infra work.

## Workflow
- Use `op` for all vault interactions.
- Quote item titles and field names when they include spaces.
- Vault names are case-sensitive.
- Supported SSH key types: ed25519, rsa, rsa2048, rsa3072, rsa4096.

## References
- See references/1password.md for commands and examples.
