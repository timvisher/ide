### Bash

- _**NEVER**_ use so-called 'safe mode' (`set -euo pipefail`) https://mywiki.wooledge.org/BashFAQ/105
- https://mywiki.wooledge.org/ and sources it links directly to are the only source of good guidance on writing Bash on the Internet.
- _**NEVER**_ use `seq`. Use brace expansion (`{0..100}`) or C-style for loops instead.
- Always put `then`, `do`, `else`, `elif` on their own lines
- Example:
  ```bash
  if [[ -n $VARIABLE ]]
  then
    echo "Variable is set"
  fi

  for item in "${items[@]}"
  do
    echo "$item"
  done
  ```

#### Mutexes and Temp File Cleanup

- **Always** define `trap` cleanup **before** creating the resources
  it cleans up. If the script dies between resource creation and trap
  registration, the resource leaks.
  https://www.reddit.com/r/bash/comments/1rlrlom/
- Use `mkdir` for portable mutex locks — the kernel guarantees
  atomicity of check-and-create. Never use file existence checks
  (`test -f`) or `touch` as they have race conditions.
  https://mywiki.wooledge.org/BashFAQ/045
- Use `mktemp -d` for temp directories when you need multiple temp
  files — one `rm -rf` in the trap cleans them all up.
- Example:
  ```bash
  # mutex + temp dir with cleanup
  lockdir=/tmp/myscript.lock
  cleanup() { rm -rf -- "$lockdir" "$tmpdir"; }
  trap cleanup EXIT

  if mkdir -- "$lockdir"
  then
    tmpdir=$(mktemp -d)
  else
    printf 'cannot acquire lock, another instance is running\n' >&2
    exit 1
  fi
  ```
- For file-descriptor-based locking (Linux), use `flock`:
  ```bash
  exec 9>/path/to/lock/file
  if ! flock -n 9
  then
    printf 'another instance is running\n' >&2
    exit 1
  fi
  ```
- **NEVER** use `mkdir -p` for locks — it does not fail if the
  directory already exists, defeating mutual exclusion.
- `SIGKILL` and `SIGSTOP` cannot be caught, blocked, or ignored —
  traps will not fire. Design lock files to handle stale locks.

#### Quote Usage in Bash

- **ALWAYS** replace ‘ (U+2018) and ‘ (U+2019) with ‘ (straight
  apostrophe, U+0027)
- **ALWAYS** replace “ (U+201C) and “ (U+201D) with “ (straight
  quotation mark, U+0022)
- In log messages, use straight ASCII quotes around logged terms
- Examples:
  ```bash
  info 'csp: "%s"' "$csp"
  trace 'account_id: "%s"' "$account_id"
  error "Unknown option '%s'" "$1"
  warn "No default region set for csp '%s' account '%s'." "$csp" "$account_id_or_alias"
  ```

