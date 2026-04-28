### AppleScript

#### Encoding gotcha

`.applescript` files in this project use heterogeneous encodings
depending on which tool last touched them. `osacompile` accepts all of
them, so they all "work" — but byte-level encoding matters for git
history and editing.

- ASCII files (no non-`0x7F` bytes) — encoding-agnostic, edit freely.
- MacRoman — single-byte encoding still produced by older AppleScript
  tooling. Identifiable by `0xC2` for `¬` (line continuation) or
  `0xD4`/`0xD5` for left/right smart double quotes (`""`). `file`
  reports "ISO-8859 text" (it can't distinguish MacRoman from Latin-1).
- UTF-16 LE with BOM (`fffe …`) — Script Editor's modern default.
  `file` reports "Unicode text, UTF-16, little-endian text".
- UTF-8 (no BOM) — what most modern programmatic edits produce. `¬`
  becomes `c2 ac` (two bytes); smart quotes become `e2 80 9c` /
  `e2 80 9d` (three bytes each).

#### Editing rules

- **Always check encoding first**: `file <name>.applescript`.
- **For ASCII files**: edit freely with the Edit tool.
- **For MacRoman files**: the Edit tool's UTF-8 round-trip mangles
  unrepresentable bytes (e.g. `0xD4` → `ef bf bd` U+FFFD). Use sed for
  byte-preserving edits — `sed -i.bak '<addr>{...}d' <file>` to delete
  lines or `sed 's/old/new/'` for in-line replacements.
- **For UTF-16 files**: same rule — Edit tool will mishandle. Use sed,
  perl, or convert to UTF-8 deliberately as a separate commit.
- **Compile-check after edits**: `osacompile -o /tmp/check.scpt <file>`.
- **Visual diff for binary-classified files**: `diff -ua <file> <(git
  show HEAD:<file>)` if `git diff` falls back to "Binary files differ".
  Example: `diff -ua "AppleScript/background noise.applescript" <(git
  show HEAD:"AppleScript/background noise.applescript")`.

#### Adding new files

Default to UTF-8 (no BOM). Avoid Script Editor's UTF-16 LE BOM unless
you specifically need Script Editor round-trip — once a file is UTF-16,
every programmatic edit becomes a sed exercise.
