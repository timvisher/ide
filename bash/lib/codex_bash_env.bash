# Sourced via BASH_ENV by *every* non-interactive bash subshell codex
# spawns — the shell snapshot validator is the motivating case, but
# tool-call subshells run this too. Must stay cheap and side-effect
# free.
#
# Codex's snapshot writer captures `set -o` options but ignores `shopt`
# state (see codex-rs/core/src/shell_snapshot.rs). If `declare -f` dumps
# a function body containing extglob (`!(...)`, `@(...)`, `+(...)`) or
# globstar patterns, the validator re-parses without those shopts and
# bails with "Shell snapshot validation failed".
#
# `globstar` requires bash >= 4, so guard it — codex picks its bash by
# PATH lookup and could land on /bin/bash (3.2) on a fresh macOS.
shopt -s extglob
shopt -s globstar 2>/dev/null || true
