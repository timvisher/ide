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

#### Adding or editing files

- **Prefer pure ASCII when feasible.** Script Editor does NOT read UTF-8
  correctly; UTF-8 is only safe for files Script Editor will never open.
  Avoid `¬` (use a temp variable to break long expressions across lines
  instead), avoid smart quotes (`""`), avoid ellipsis (`…` -> `...`).
  Pure-ASCII files have no encoding ambiguity and edit cleanly.
- **When non-ASCII is unavoidable** (and the file may be opened in
  Script Editor), use the encoding Script Editor produces — MacRoman
  by default, UTF-16 LE BOM if Script Editor's preferences are set
  that way. Add a `working-tree-encoding` entry to `.gitattributes`:
  ```
  AppleScript/some[[:space:]]file.applescript diff working-tree-encoding=MACINTOSH
  AppleScript/some[[:space:]]other.applescript diff working-tree-encoding=UTF-16LE-BOM
  ```
  Git will then store the file as UTF-8 internally and round-trip the
  working-tree bytes through `iconv` on checkout/checkin.
- **Never write UTF-8 to a file Script Editor will edit.** Doing so
  breaks Script Editor's parser at any non-ASCII byte.
