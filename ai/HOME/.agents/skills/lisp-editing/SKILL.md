---
name: lisp-editing
description: Batch Emacs + paredit workflow for editing Emacs Lisp (.el) files with structure-safe operations, edit-programs, and command references. Use when a request involves modifying Emacs Lisp code via paredit, Emacs batch execution, or the agent-edit-lisp wrapper.
---

# Lisp editing with paredit (Emacs batch)

## Overview
Use batch Emacs with a skill-local init and a single edit-program file to apply structure-safe edits to Emacs Lisp files. The edit program is a single top-level `(progn ...)` that navigates, runs paredit commands, and reindents the edited defun(s).

## Workflow
1. Write an edit program file with a single top-level `(progn ...)`.
2. Run `scripts/agent-edit-lisp TARGET_FILE EDIT_PROGRAM`.
3. Review the diff produced by the edit.

## Edit program requirements
- Use a single top-level `(progn ...)` form.
- Perform as many edits as needed; multiple defuns are fine.
- Do not open the target file; Emacs already visits `TARGET_FILE`.
- Navigate explicitly before each edit (see Navigation guidance).
- Use paredit commands for all structural delimiter changes.
  - Insert strings with `paredit-doublequote`, `insert` the contents, then `paredit-doublequote` to move over the closing quote.
  - Insert atoms (symbols, numbers) with `insert` only when point is in a safe context (inside a string or symbol).
- Prefer paredit commands for structural deletes, kills, wraps, splices, raises, slurps, and barfs.
- Reindent the full edited defun after each change:
  - `(save-excursion (mark-defun) (indent-region (region-beginning) (region-end)))`
- Avoid evaluating user code.

## Navigation guidance
- Use `goto-char` for exact positions.
- Use `imenu` to jump to a defun by name.
- Do not pass the raw index alist to `imenu`; call `(imenu "defun-name")` directly. If you need the index, use `imenu--make-index-alist` and then `assoc`/`cdr` to get a marker.
- Use `beginning-of-defun` and `end-of-defun` for relative movement.
- Use `down-list`, `forward-sexp`, `up-list`, and `backward-up-list` for structural navigation.

## Tooling
- `scripts/agent-edit-lisp` wraps `emacs -Q --batch` with a skill-local init.
- `emacs.d/init.el`:
  - Enables `paredit-mode` for Emacs Lisp buffers.
  - Asserts `emacs-lisp-mode` via `find-file-hook`.
  - Exposes `agent-run`, which loads the edit program and saves the buffer.

## Paredit command reference
- See `references/paredit-cheatsheet.md` for the full paredit command surface area (derived from `~/Downloads/paredit.pdf`).
