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

#### Usage and Help Output

- Usage text is **diagnostic by default**: most of the time it is printed
  because the caller made a mistake, so it belongs on **stderr** with a
  non-zero exit.
- An explicit `--help` is different -- the caller asked for that output, so
  it goes to **stdout** with exit 0. `cmd --help | less` must work.
- Do not append `>&2` at each error site. Split the two, name both, and let
  every call site be a bare call:
  ```bash
  # content, on stdout
  show_help() {
    cat <<'EOF'
  Usage: mytool <subcommand> [args...]
  EOF
  }

  # diagnostic wrapper: the common case
  usage() {
    show_help >&2
  }

  case ${1-} in
    -h|--help)
      show_help          # asked for it: stdout, exit 0
      exit 0
      ;;
    '')
      usage              # caller error: stderr, non-zero
      exit 1
      ;;
  esac
  ```
- Getting this backwards is not cosmetic. A caller doing
  `v=$(mytool query 2>/dev/null)` keeps stdout and throws stderr away, so
  usage text leaking to stdout during a failure becomes the value of `$v`
  and passes a `[[ -n $v ]]` guard.
- A usage function that serves only an error path (nothing routes `--help`
  to it) can bake `>&2` into its own definition.
- **Tests must assert the two streams separately.** `2>&1` cannot tell them
  apart, so a test that captures it will pass while `--help | less` is
  broken. Assert that `cmd --help 2>/dev/null` produces output and that
  `cmd 2>/dev/null` produces none.
