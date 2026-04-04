### Emacs Lisp Testing (ERT)

- Use ERT (Emacs Lisp Regression Testing) for testing Emacs Lisp code
- Run tests in batch mode using the pattern that matches the target:
  - **Testing your config** (`~/git/ide/emacs/` or `~/.config/timvisher/ide/emacs/`):
    ```bash
    emacs --batch \
      --eval "(require 'package)" \
      --eval "(package-initialize)" \
      --eval '(load "~/.config/emacs/init.el")' \
      --eval '(load "/path/to/test-file.el")' \
      --eval '(ert-run-tests-batch-and-exit)'
    ```
  - **Testing public libraries** (e.g., `~/git/timvisher-dd/agent-shell-plus/`):
    ```bash
    emacs --batch -Q -L . \
      -l /path/to/test-file.el \
      -f ert-run-tests-batch-and-exit
    ```
- Test files should follow naming convention `*-test.el`
- Test functions should use prefix `test-` for automatic discovery
- Common test patterns:
  - Use `with-temp-buffer` for buffer manipulation tests
  - Use `unwind-protect` to ensure cleanup code runs
  - Use `make-temp-file` for temporary files, always delete in
    `unwind-protect`
  - When testing functions that modify global state (like kill ring), save
    and restore state for proper test isolation:
    ```elisp
    (let ((saved-kill-ring kill-ring))
      (unwind-protect
          ;; test code here
        (setq kill-ring saved-kill-ring)))
    ```
- Test documentation:
  - Provide clear docstrings explaining what each test verifies
  - Use multi-line docstrings for complex tests
  - Document any test isolation measures
- Test file structure:
  - Include commentary section explaining overall test purpose
  - Document any special test isolation requirements
  - Note any dependencies (e.g., "ai.el is already loaded by init.el")
- When testing public libraries in batch mode, do NOT load init.el; rely on `-Q`
  and load only the test files you need
- When testing your config, load init.el once in the batch command; do not load
  it again in test files

### Batch Mode

Emacs `--batch` has EVERYTHING a GUI/TUI Emacs does except a TTY.
Buffers, processes, process filters, comint, `display-buffer`, timers
— all work. Do NOT add workarounds or special-case batch mode.

For long-running async work (e.g., agent-shell sessions), use the
timer + `accept-process-output` pattern:

```elisp
;; State flag
(defvar my--done nil)

;; Hard timeout
(run-at-time timeout-seconds nil
             (lambda () (my--finish "timeout")))

;; Poll timer: observe when the shell returns to prompt
(run-at-time poll-interval poll-interval
             (lambda ()
               (when-let ((buf (agent-shell--shell-buffer :no-create t)))
                 (with-current-buffer buf
                   (let ((busy (ignore-errors (shell-maker-busy))))
                     ;; state machine: sent → seen-busy → not-busy = done
                     ...)))))

;; Event loop — accept-process-output keeps timers and process
;; filters firing. Do NOT use (while t (sit-for N)).
(while (not my--done)
  (accept-process-output nil poll-interval))
```

See `~/git/timvisher-dd/agent-shell-plus/protocol-exp-20260218/scripts/`
for full examples (`agent-shell-perf-repro.el`,
`agent-shell-large-output-repro.el`, `agent-shell-focus-loss-repro.el`).

### Language Quirks & Best Practices

- **Truthiness:** In Emacs Lisp, `nil` is the *only* falsy value. Empty strings `""`, empty vectors `[]`, and the number `0` are all truthy. When branching logic relies on whether a string has content, test it explicitly.
- **`string-empty-p` and `nil`:** The function `string-empty-p` evaluates to `nil` if passed `nil` (because `nil` is not equal to `""`). This means `nil` is technically evaluated as "not empty" if you use `string-empty-p` as your sole check. Use `(or (null str) (string-empty-p str))` to robustly check if a string variable is missing or empty.
- **String functions and `nil`:** Functions like `string-trim` throw a `wrong-type-argument stringp, nil` error if passed `nil`. Ensure variables are non-nil before invoking strict string operations.
- **`concat` and `nil`:** The `concat` function silently ignores `nil` values. For example, `(concat "\n\n" nil "\n\n")` results in `"\n\n\n\n"`. This can cause unintended formatting artifacts if you assume a falsy check on `nil` will prevent evaluation.
- **Multibyte Character Limits:** When truncating strings or buffers by byte length, landing in the middle of a multibyte UTF-8 character and using `(byte-to-position)` will safely return the *start* of that character. While this prevents splitting or corrupting characters, it means the resulting substring will contain the full multibyte character and *exceed* the requested maximum byte limit. To strictly enforce a maximum byte limit, detect if you landed mid-character (e.g. `(< (position-bytes pos) target-byte)`) and step forward one character position.
