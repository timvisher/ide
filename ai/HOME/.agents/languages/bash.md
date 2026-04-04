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

