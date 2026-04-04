# 1Password CLI (`op`)

- Use `op` CLI to interact with 1Password vaults and items
- Common operations:
  - Create SSH key: `op item create --category 'SSH Key' --title '<title>'
    --vault '<vault>' --ssh-generate-key=<type>`
  - Get field value: `op item get '<title>' --vault '<vault>' --fields
    '<field-name>'`
  - List items: `op item list --vault '<vault>'`
- SSH key generation supports: `ed25519`, `rsa`, `rsa2048`, `rsa3072`,
  `rsa4096`
- When passing item titles or field names with spaces, use quotes
- Vault names are case-sensitive

