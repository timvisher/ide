### AppleScript

- AppleScript files (`.applescript`) are UTF-16 little-endian encoded,
  which git treats as binary
- When `git diff` shows an AppleScript file as binary, use `diff -ua
  <file> <(git show HEAD:<file>)` to see a proper unified diff of what
  actually changed
- Example: `diff -ua "AppleScript/background noise.applescript" <(git
  show HEAD:"AppleScript/background noise.applescript")`
