;;; timvisher-agent-shell-start-test.el --- Tests for timvisher-agent-shell-start -*- lexical-binding: t; -*-

;;; Commentary:
;; Starting a shell per agent and handing it the prompt, with
;; agent-shell's entry points stubbed, so no agent runs.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'timvisher-agent-shell-start)

(defmacro test-timvisher-agent-shell-start--with-stubs (&rest body)
  "Run BODY with agent-shell's start and insert stubbed.

BODY sees `started' (each start's arguments), `inserted' (each insert's
arguments), `shell' (the buffer the stubbed start returns) and
`session-id' (what that shell reports; nil until set)."
  (declare (indent 0))
  `(let* ((shell (generate-new-buffer "shell-started"))
          (started nil) (inserted nil) (session-id nil))
     (unwind-protect
         (cl-letf (((symbol-function 'agent-shell-anthropic-make-claude-code-config)
                    (lambda () 'claude-config))
                   ((symbol-function 'agent-shell-openai-make-codex-config)
                    (lambda () 'codex-config))
                   ((symbol-function 'agent-shell--start)
                    (lambda (&rest args) (push args started) shell))
                   ((symbol-function 'agent-shell--insert-to-shell-buffer)
                    (lambda (&rest args) (push args inserted)))
                   ((symbol-function 'agent-shell--state)
                    (lambda () `((:session . ((:id . ,session-id)))))))
           ,@body)
       (when (buffer-live-p shell) (kill-buffer shell)))))

(defun test-timvisher-agent-shell-start--parse (json)
  "Parse JSON into an alist."
  (json-parse-string json :object-type 'alist :null-object nil :false-object nil))

(ert-deftest test-timvisher-agent-shell-start-claude-with-prompt ()
  "Claude starts unfocused with a new session and gets the trimmed prompt."
  (let ((prompt (make-temp-file "tvass" nil nil "From the test agent\n\nGo.\n\n")))
    (unwind-protect
        (test-timvisher-agent-shell-start--with-stubs
          (let ((status (test-timvisher-agent-shell-start--parse
                         (timvisher-agent-shell-start "claude" prompt))))
            (should (equal "shell-started" (alist-get 'buffer status)))
            (should (eq t (alist-get 'live status)))
            (should-not (alist-get 'session_id status)))
          (should (equal '((:config claude-config :session-strategy new :new-session t :no-focus t))
                         started))
          (should (equal `((:shell-buffer ,shell :text "From the test agent\n\nGo." :submit t :no-focus t))
                         inserted)))
      (delete-file prompt))))

(ert-deftest test-timvisher-agent-shell-start-codex-without-prompt ()
  "Codex starts with its own config, and no prompt means nothing inserted."
  (test-timvisher-agent-shell-start--with-stubs
    (timvisher-agent-shell-start "codex")
    (should (eq 'codex-config (plist-get (car started) :config)))
    (should-not inserted)))

(ert-deftest test-timvisher-agent-shell-start-unknown-agent ()
  "An unknown agent signals and starts nothing."
  (test-timvisher-agent-shell-start--with-stubs
    (should-error (timvisher-agent-shell-start "gemini"))
    (should-not started)))

(ert-deftest test-timvisher-agent-shell-start-status-reports-the-session ()
  "Status shows the session id once set, and a killed shell as not live."
  (test-timvisher-agent-shell-start--with-stubs
    (setq session-id "sess-new")
    (should (equal "sess-new" (alist-get 'session_id (test-timvisher-agent-shell-start--parse
                                                       (timvisher-agent-shell-start-status "shell-started")))))
    (kill-buffer shell)
    (let ((status (test-timvisher-agent-shell-start--parse
                   (timvisher-agent-shell-start-status "shell-started"))))
      (should-not (alist-get 'live status))
      (should-not (alist-get 'session_id status)))))

(provide 'timvisher-agent-shell-start-test)
;;; timvisher-agent-shell-start-test.el ends here
