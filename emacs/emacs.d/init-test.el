;;; init-test.el --- Tests for init.el functions -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for source-link and Claude source link functions defined in init.el
;;
;; These tests verify the Claude source link generation functionality, which
;; creates references in the format "@/path/to/file:line" or "@/path/to/file:start-end".
;;
;; Test Isolation:
;; The function being tested modifies global state (the kill ring), so tests must
;; save and restore kill ring state to ensure proper isolation between test runs.

;;; Code:

(require 'ert)

;;; Tests for timvisher-load-op-environment-variables

(defmacro test-timvisher-op--with-env (bindings &rest body)
  "Run BODY with the two agent key variables set as in BINDINGS, restored after."
  (declare (indent 1))
  `(let ((process-environment (copy-sequence process-environment)))
     (setenv "OPENAI_API_KEY" nil)
     (setenv "ANTHROPIC_API_KEY" nil)
     (dolist (b ,bindings) (setenv (car b) (cdr b)))
     ,@body))

(ert-deftest test-timvisher-load-op-env-no-op-runs-nothing ()
  "Without op on PATH (a workspace) nothing runs and no op:// is left set."
  (test-timvisher-op--with-env '(("ANTHROPIC_API_KEY" . "op://Private/x/y"))
    (let ((ran nil))
      (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil))
                ((symbol-function 'call-process-shell-command)
                 (lambda (&rest _) (setq ran t) 0)))
        (should (= 0 (timvisher-load-op-environment-variables)))
        (should-not ran)
        (should-not (getenv "ANTHROPIC_API_KEY"))
        (should-not (getenv "OPENAI_API_KEY"))))))

(ert-deftest test-timvisher-load-op-env-real-values-skip-op ()
  "Real values already in the environment mean op is never run."
  (test-timvisher-op--with-env '(("ANTHROPIC_API_KEY" . "sk-a") ("OPENAI_API_KEY" . "sk-o"))
    (let ((ran nil))
      (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/usr/bin/op"))
                ((symbol-function 'call-process-shell-command)
                 (lambda (&rest _) (setq ran t) 0)))
        (should (= 0 (timvisher-load-op-environment-variables)))
        (should-not ran)
        (should (equal (getenv "ANTHROPIC_API_KEY") "sk-a"))))))

(ert-deftest test-timvisher-load-op-env-resolves-through-op ()
  "With op, the unresolved variables are set from op run's output."
  (test-timvisher-op--with-env '(("OPENAI_API_KEY" . "sk-o"))
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/usr/bin/op"))
              ((symbol-function 'call-process-shell-command)
               (lambda (command _infile buffer &rest _)
                 (should (string-match-p "op run" command))
                 (with-current-buffer (if (eq buffer t) (current-buffer) buffer)
                   (insert "PATH=/bin\nANTHROPIC_API_KEY=sk-resolved\n"))
                 0)))
      (should (= 1 (timvisher-load-op-environment-variables)))
      (should (equal (getenv "ANTHROPIC_API_KEY") "sk-resolved"))
      (should (equal (getenv "OPENAI_API_KEY") "sk-o")))))

(ert-deftest test-timvisher-load-op-env-failure-warns-not-errors ()
  "A failing op run warns, leaves no op:// placeholder, and doesn't signal."
  (test-timvisher-op--with-env '()
    (let ((warned nil))
      (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/usr/bin/op"))
                ((symbol-function 'call-process-shell-command) (lambda (&rest _) 1))
                ((symbol-function 'display-warning) (lambda (&rest _) (setq warned t))))
        (should (= 0 (timvisher-load-op-environment-variables)))
        (should warned)
        (should-not (getenv "ANTHROPIC_API_KEY"))
        (should-not (getenv "OPENAI_API_KEY"))))))

(ert-deftest test-timvisher-agent-shell-authentication-key-or-login ()
  "An API key in the environment is used; without one, login."
  (test-timvisher-op--with-env '(("ANTHROPIC_API_KEY" . "sk-a"))
    (let ((maker (lambda (&rest args) args)))
      (should (equal (timvisher-agent-shell-authentication maker "ANTHROPIC_API_KEY")
                     '(:api-key "sk-a")))
      (should (equal (timvisher-agent-shell-authentication maker "OPENAI_API_KEY")
                     '(:login t))))))

;;; Tests for timvisher-agent-shell-mcp-servers

(ert-deftest test-timvisher-agent-shell-mcp-servers-brew-from-path ()
  "The homebrew MCP server runs whichever brew `executable-find' finds.

A Linux workspace has /home/linuxbrew/.linuxbrew/bin/brew, not
/opt/homebrew/bin/brew."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (name &optional _remote)
               (when (equal name "brew")
                 "/home/linuxbrew/.linuxbrew/bin/brew"))))
    (let ((homebrew (seq-find (lambda (server)
                                (equal (alist-get 'name server) "homebrew"))
                              (timvisher-agent-shell-mcp-servers))))
      (should homebrew)
      (should (equal (alist-get 'command homebrew)
                     "/home/linuxbrew/.linuxbrew/bin/brew"))
      (should (equal (alist-get 'args homebrew) '("mcp-server"))))))

(ert-deftest test-timvisher-agent-shell-mcp-servers-no-brew ()
  "Without brew on the path there is no homebrew MCP server."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (&rest _) nil)))
    (should-not (seq-find (lambda (server)
                            (equal (alist-get 'name server) "homebrew"))
                          (timvisher-agent-shell-mcp-servers)))))

;;; Tests for source-link--get-line-range

(ert-deftest test-source-link--get-line-range-single-line ()
  "Test getting line range for a single line (no region).

Verifies that when point is on a line without an active region, the function
returns a range where start-line and end-line are the same."
  (with-temp-buffer
    (insert "line 1\nline 2\nline 3\n")
    (goto-char (point-min))
    (forward-line 1)  ; Move to line 2
    (let ((range (source-link--get-line-range)))
      (should (= 2 (plist-get range :start-line)))
      (should (= 2 (plist-get range :end-line))))))

(ert-deftest test-source-link--get-line-range-multi-line ()
  "Test getting line range for a multi-line region.

Verifies that when a region spans multiple lines, the function returns the
correct start and end line numbers for the entire region."
  (with-temp-buffer
    (insert "line 1\nline 2\nline 3\nline 4\n")
    (goto-char (point-min))
    (forward-line 1)  ; Start at line 2
    (set-mark (point))
    (forward-line 2)  ; End at line 4
    (activate-mark)
    (let ((range (source-link--get-line-range)))
      (should (= 2 (plist-get range :start-line)))
      (should (= 4 (plist-get range :end-line))))))

(ert-deftest test-source-link--get-line-range-first-line ()
  "Test getting line range for the first line.

Verifies edge case: when point is on the first line (line 1), the function
correctly returns 1 for both start and end line numbers."
  (with-temp-buffer
    (insert "line 1\nline 2\nline 3\n")
    (goto-char (point-min))
    (let ((range (source-link--get-line-range)))
      (should (= 1 (plist-get range :start-line)))
      (should (= 1 (plist-get range :end-line))))))

(ert-deftest test-source-link--get-line-range-region-within-line ()
  "Test getting line range for a region within a single line.

Verifies that when a region is active but entirely within a single line, the
function returns the same line number for both start and end (treating it as
a single-line range)."
  (with-temp-buffer
    (insert "line 1\nthis is a long line with content\nline 3\n")
    (goto-char (point-min))
    (forward-line 1)
    (forward-char 5)  ; Position in middle of line 2
    (set-mark (point))
    (forward-char 10) ; Select some chars on same line
    (activate-mark)
    (let ((range (source-link--get-line-range)))
      (should (= 2 (plist-get range :start-line)))
      (should (= 2 (plist-get range :end-line))))))

;;; Tests for timvisher-EXP-claude-source-link

(ert-deftest test-claude-source-link-single-line ()
  "Test Claude source link for a single line.

Verifies that when point is on a single line (no active region), the generated
link has the format @/path/to/file:LINE without a range."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))  ; Save kill ring state for isolation
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (forward-line 1)  ; Move to line 2
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-match-p (regexp-quote test-file) link))
              (should (string-match-p ":2$" link))
              (should-not (string-match-p ":[0-9]+-[0-9]+$" link)))))
      (setq kill-ring saved-kill-ring)  ; Restore kill ring
      (delete-file test-file))))

(ert-deftest test-claude-source-link-multi-line ()
  "Test Claude source link for a multi-line region.

Verifies that when a region spans multiple lines, the generated link has the
format @/path/to/file:START-END with both line numbers."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))  ; Save kill ring state for isolation
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\nline 4\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (forward-line 1)  ; Start at line 2
            (set-mark (point))
            (forward-line 2)  ; End at line 4
            (activate-mark)
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-match-p (regexp-quote test-file) link))
              (should (string-match-p ":2-4$" link)))))
      (setq kill-ring saved-kill-ring)  ; Restore kill ring
      (delete-file test-file))))

(ert-deftest test-claude-source-link-format ()
  "Test that Claude source link uses the @ prefix format.

Verifies that the generated link starts with @ and matches the expected pattern.
Note: On line 1 without region, no line number is included (references whole file)."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))  ; Save kill ring state for isolation
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (forward-line 1)  ; Move to line 2 to avoid line-1 special case
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-prefix-p "@" link))
              (should (string-match-p "^@.+:[0-9]+$" link)))))
      (setq kill-ring saved-kill-ring)  ; Restore kill ring
      (delete-file test-file))))

(ert-deftest test-claude-source-link-no-file ()
  "Test that Claude source link errors when buffer has no file.

Verifies that the function signals an error when called in a buffer that is not
visiting a file, since there's no file path to include in the link."
  (with-temp-buffer
    (insert "some content\n")
    (should-error (timvisher-EXP-claude-source-link)
                  :type 'error)))

(ert-deftest test-claude-source-link-line-1-no-region ()
  "Test Claude source link on line 1 without region references whole file.

When point is on line 1 with no active region, the link should be @/path/to/file
without any line number, referencing the entire file."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))  ; On line 1
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string= link (format "@%s" test-file)))
              (should-not (string-match-p ":[0-9]" link)))))
      (setq kill-ring saved-kill-ring)
      (delete-file test-file))))

(ert-deftest test-claude-source-link-line-1-with-region ()
  "Test Claude source link on line 1 with region references line 1 only.

When point is on line 1 with an active region, the link should respect the
explicit selection and include :1 to reference specifically line 1."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (set-mark (point))
            (end-of-line)
            (activate-mark)
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-match-p (regexp-quote test-file) link))
              (should (string-match-p ":1$" link)))))
      (setq kill-ring saved-kill-ring)
      (delete-file test-file))))

(ert-deftest test-claude-source-link-dired-single-file ()
  "Test Claude source link in dired for file at point.

In dired with no marks and no region, should @ the file at point."
  (let ((test-dir (make-temp-file "test_dired" t))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (let ((test-file-1 (expand-file-name "file1.txt" test-dir))
                (test-file-2 (expand-file-name "file2.txt" test-dir)))
            (write-region "content1\n" nil test-file-1)
            (write-region "content2\n" nil test-file-2)
            (let ((dired-buf (dired test-dir)))
              (with-current-buffer dired-buf
                ;; Ensure we're in the dired buffer
                (should (eq major-mode 'dired-mode))
                ;; Find first actual file (not . or ..)
                (goto-char (point-min))
                (while (and (not (eobp))
                            (let ((file (dired-get-filename nil t)))
                              (or (null file)
                                  (member (file-name-nondirectory file) '("." "..")))))
                  (dired-next-line 1))
                (timvisher-EXP-claude-source-link)
                (let ((link (car kill-ring)))
                  (should (string-prefix-p "@" link))
                  (should (or (string-match-p "file1\\.txt" link)
                              (string-match-p "file2\\.txt" link))))))))
      (setq kill-ring saved-kill-ring)
      (delete-directory test-dir t))))

(ert-deftest test-claude-source-link-dired-marked-files ()
  "Test Claude source link in dired for marked files.

In dired with marked files, should @ all marked files as newline-separated list."
  (let ((test-dir (make-temp-file "test_dired" t))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (let ((test-file-1 (expand-file-name "file1.txt" test-dir))
                (test-file-2 (expand-file-name "file2.txt" test-dir)))
            (write-region "content1\n" nil test-file-1)
            (write-region "content2\n" nil test-file-2)
            (let ((dired-buf (dired test-dir)))
              (with-current-buffer dired-buf
                ;; Ensure we're in the dired buffer
                (should (eq major-mode 'dired-mode))
                ;; Find and mark both actual files (not . or ..)
                (goto-char (point-min))
                (let ((files-marked 0))
                  (while (and (not (eobp)) (< files-marked 2))
                    (let ((file (dired-get-filename nil t)))
                      (when (and file
                                 (not (member (file-name-nondirectory file) '("." ".."))))
                        (dired-mark 1)  ; Mark and move to next line
                        (setq files-marked (1+ files-marked)))
                      (unless (and file
                                   (not (member (file-name-nondirectory file) '("." ".."))))
                        (dired-next-line 1)))))
                (timvisher-EXP-claude-source-link)
                (let ((link (car kill-ring)))
                  (should (string-match-p "file1\\.txt" link))
                  (should (string-match-p "file2\\.txt" link))
                  (should (string-match-p "\n" link)))))))
      (setq kill-ring saved-kill-ring)
      (delete-directory test-dir t))))

;;; Tests for the forge/ghub gh-CLI auth-source backend

(require 'cl-lib)

(ert-deftest test-ide-forge--gh-token-trims-output ()
  "`ide-forge--gh-token' returns the gh token with surrounding whitespace removed."
  (cl-letf (((symbol-function 'shell-command-to-string)
             (lambda (&rest _) "gho_abc123\n")))
    (should (equal (ide-forge--gh-token "timvisher-dd") "gho_abc123"))))

(ert-deftest test-ide-forge--gh-token-empty-is-nil ()
  "`ide-forge--gh-token' returns nil when gh emits no token."
  (cl-letf (((symbol-function 'shell-command-to-string)
             (lambda (&rest _) "\n")))
    (should-not (ide-forge--gh-token "timvisher-dd"))))

(ert-deftest test-ide-forge--gh-auth-search-returns-account-token ()
  "The search returns a function secret that mints a token for the account.

The account is the part of the ghub USER key before the ^PACKAGE suffix."
  (cl-letf (((symbol-function 'ide-forge--gh-token)
             (lambda (account) (format "TOKEN:%s" account))))
    (let* ((result (car (ide-forge--gh-auth-search
                         :host "api.github.com" :user "timvisher-dd^forge")))
           (secret (plist-get result :secret)))
      (should (equal (plist-get result :user) "timvisher-dd^forge"))
      (should (functionp secret))
      (should (equal (funcall secret) "TOKEN:timvisher-dd")))))

(ert-deftest test-ide-forge--gh-auth-search-matches-both-hosts ()
  "Both api.github.com and github.com are matched; account is extracted."
  (cl-letf (((symbol-function 'ide-forge--gh-token) #'identity))
    (dolist (host '("api.github.com" "github.com"))
      (should (equal (funcall (plist-get
                               (car (ide-forge--gh-auth-search
                                     :host host :user "tim-visher_ddog^ghub"))
                               :secret))
                     "tim-visher_ddog")))))

(ert-deftest test-ide-forge--gh-auth-search-ignores-other-hosts ()
  "Non-GitHub hosts fall through so other auth-source backends handle them."
  (should-not (ide-forge--gh-auth-search :host "gitlab.com" :user "x^forge")))

(ert-deftest test-ide-forge--gh-auth-search-requires-package-suffix ()
  "A USER without a ^PACKAGE suffix is not handled by this backend."
  (should-not (ide-forge--gh-auth-search :host "api.github.com" :user "plainuser")))

(ert-deftest test-ide-forge--gh-auth-backend-registered ()
  "The backend parser and source are registered with auth-source."
  (should (memq #'ide-forge--gh-auth-parser auth-source-backend-parser-functions))
  (should (memq 'gh-forge auth-sources))
  (should (ide-forge--gh-auth-parser 'gh-forge))
  (should-not (ide-forge--gh-auth-parser 'not-our-source)))

;;; Tests for ide-control-server-start

(defmacro test-ide-control-server--with-fresh-server (&rest body)
  "Run BODY with no live server and a socket dir short enough for macOS.

The suite's throwaway $TMPDIR pushes the default socket path past the
104-byte limit, so sockets go under /tmp instead.  Any server BODY
starts is deleted afterwards."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/ics" t))
          (server-process nil)
          (server-name server-name))
     (unwind-protect
         (progn ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(ert-deftest test-ide-control-server-start-serves-timvisher-pid ()
  "Starting gives a live timvisher-<pid> server that emacsclient reaches."
  (test-ide-control-server--with-fresh-server
    (ide-control-server-start)
    (should (process-live-p server-process))
    (should (equal server-name (format "timvisher-%d" (emacs-pid))))
    (with-temp-buffer
      (let ((client (make-process
                     :name "test-emacsclient"
                     :buffer (current-buffer)
                     :sentinel #'ignore
                     :command (list "emacsclient"
                                    "-s" (expand-file-name server-name
                                                           server-socket-dir)
                                    "--eval" "(* 6 7)")))
            (deadline (+ (float-time) 10)))
        (while (and (process-live-p client) (< (float-time) deadline))
          (accept-process-output nil 0.1))
        (should (equal "42\n" (buffer-string)))))))

(ert-deftest test-ide-control-server-start-is-idempotent ()
  "A second call keeps the running server and its name."
  (test-ide-control-server--with-fresh-server
    (ide-control-server-start)
    (let ((process server-process))
      (ide-control-server-start)
      (should (eq process server-process))
      (should (equal (format "timvisher-%d" (emacs-pid)) server-name)))))

(ert-deftest test-ide-control-server-start-survives-overlong-socket-path ()
  "A socket path over the OS limit leaves no server but does not signal."
  (let ((server-socket-dir (concat "/tmp/" (make-string 120 ?x)))
        (server-process nil)
        (server-name server-name))
    (ide-control-server-start)
    (should-not (process-live-p server-process))))

(ert-deftest test-ide-control-server-start-keeps-existing-server-name ()
  "An Emacs already serving under another name is left alone."
  (let ((server-name "some-other-server")
        (server-process (make-pipe-process :name "fake-server" :noquery t)))
    (unwind-protect
        (progn
          (ide-control-server-start)
          (should (equal "some-other-server" server-name)))
      (delete-process server-process))))

(provide 'init-test)
;;; init-test.el ends here
