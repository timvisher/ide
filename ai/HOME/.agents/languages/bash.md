### Bash

- _**NEVER**_ enable so-called 'safe mode' (`set -euo pipefail`) globally,
  whether the flags appear together or separately. Do your own error checking
  instead — see "Error Handling" below, which also covers the one scoped use
  of `pipefail` that is fine. https://mywiki.wooledge.org/BashFAQ/105 and
  pitfall 60 on https://mywiki.wooledge.org/BashPitfalls
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

#### Error Handling

- The shell cannot detect errors. All it has is a command's exit status, and
  plenty of commands exit non-zero without anything being wrong. That is why
  the automatic mechanisms do not work, and why you check the things you
  actually care about, where you care about them.
- `-e` (`errexit`) is the worst of the three. Its rules for when to abort are,
  per BashFAQ/105, "extremely convoluted", they still miss simple cases, and
  they have changed between Bash versions. Commands in an `if` test, and every
  command in a pipeline but the last, are silently immune — so it gives you
  false confidence exactly where you wanted a guarantee. The FAQ's own advice:
  "don't use set -e. Add your own error checking instead."
- `-u` (`nounset`) breaks correct scripts on ordinary idioms — optional
  positional parameters, empty arrays. wooledge takes no side on it
  (BashFAQ/112), calling it controversial and warning it is not always safe to
  add to the top of a script. Use `"${1-}"` rather than reaching for it.
- `pipefail` is reasonable for one specific pipeline that needs it, but
  _**NEVER**_ globally at the top of a file. Scope it so you cannot clobber a
  caller that already set it — a subshell, or `local -` inside a function:
  ```bash
  count=$(
    set -o pipefail
    grep -c -- "$pattern" "$file" | head -1
  )

  parse_feed() {
    local -                 # restores all shell options on return
    set -o pipefail
    curl -fsS -- "$url" | gunzip
  }
  ```
- Check the call, report it, and decide what to do:
  ```bash
  if ! cp -- "$src" "$dst"
  then
    printf 'cp failed: "%s" -> "%s"\n' "$src" "$dst" >&2
    exit 1
  fi
  ```
- Accumulate when you want every failure reported rather than the first one
  aborting the run — this is what a test suite wants:
  ```bash
  failures=0

  check_one "$case" || (( failures += 1 ))

  if (( 0 < failures ))
  then
    exit 1
  fi
  ```
- Prefer `(( x += 1 ))` to `(( x++ ))`. Post-increment evaluates to the value
  *before* the bump, so `(( x++ ))` exits non-zero when `x` was 0 — which
  under `errexit` kills the script the first time it counts anything, and is
  why safe-mode codebases fill up with `|| true`. `(( x += 1 ))` evaluates to
  the new value, so it only exits non-zero when the result is genuinely 0.
  Without `errexit` neither one aborts anything, and the `|| true` can go.

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

- **ALWAYS** replace ‘ (U+2018) and ’ (U+2019) with ' (straight
  apostrophe, U+0027)
- **ALWAYS** replace “ (U+201C) and ” (U+201D) with " (straight
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
