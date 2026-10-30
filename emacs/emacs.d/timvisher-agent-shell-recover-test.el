;;; timvisher-agent-shell-recover-test.el --- Tests for timvisher-agent-shell-recover -*- lexical-binding: t; -*-

;;; Commentary:
;; Wedge verdicts from stubbed shell state, and the recovery fork's
;; ready, failed and unsupported paths with agent-shell's entry points
;; stubbed, so no agent runs.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'timvisher-agent-shell-recover)

(defvar test-timvisher-agent-shell-recover--states nil
  "Alist of buffer to the agent-shell state the stubs report for it.")

(defmacro test-timvisher-agent-shell-recover--with-stubs (status &rest body)
  "Run BODY with agent-shell stubbed to report STATUS for every shell.

Each shell's state comes from `test-timvisher-agent-shell-recover--states'."
  (declare (indent 1))
  `(let ((test-timvisher-agent-shell-recover--states nil))
     (cl-letf (((symbol-function 'agent-shell-buffers)
                (lambda () (mapcar #'car test-timvisher-agent-shell-recover--states)))
               ((symbol-function 'agent-shell--state)
                (lambda () (alist-get (current-buffer) test-timvisher-agent-shell-recover--states)))
               ((symbol-function 'agent-shell-status)
                (lambda (&rest _) ,status)))
       ,@body)))

(defun test-timvisher-agent-shell-recover--shell (session-id &rest state)
  "Make a fake shell buffer for SESSION-ID with extra STATE pairs."
  (let ((buffer (generate-new-buffer (concat "shell-" session-id))))
    (setf (alist-get buffer test-timvisher-agent-shell-recover--states)
          (append `((:session . ((:id . ,session-id))))
                  (mapcar (lambda (pair) (cons (car pair) (cadr pair)))
                          (seq-partition state 2))))
    buffer))

(defun test-timvisher-agent-shell-recover--report (session-id &optional quiet-seconds)
  "Return SESSION-ID's wedge report parsed into an alist."
  (json-parse-string (timvisher-agent-shell-wedge-report session-id quiet-seconds)
                     :object-type 'alist :array-type 'list))

(defmacro test-timvisher-agent-shell-recover--with-process (var &rest body)
  "Run BODY with VAR bound to a live process, deleted afterwards."
  (declare (indent 1))
  `(let ((,var (make-pipe-process :name "test-agent" :noquery t)))
     (unwind-protect (progn ,@body)
       (delete-process ,var))))

(defconst test-timvisher-agent-shell-recover--prompt
  '((:method . "session/prompt") (:params . nil))
  "An in-flight session/prompt request.")

(ert-deftest test-timvisher-agent-shell-recover-healthy-busy-shell-is-not-wedged ()
  "Busy with a live agent, a prompt in flight and recent activity is fine."
  (test-timvisher-agent-shell-recover--with-stubs 'busy
    (test-timvisher-agent-shell-recover--with-process process
      (let ((buffer (test-timvisher-agent-shell-recover--shell
                     "s1" :client `((:process . ,process))
                     :active-requests (list test-timvisher-agent-shell-recover--prompt)
                     :last-activity-time (time-subtract nil 10))))
        (unwind-protect
            (let ((report (test-timvisher-agent-shell-recover--report "s1")))
              (should (eq :false (alist-get 'wedged report)))
              (should (equal "busy" (alist-get 'status report)))
              (should (<= 10 (alist-get 'seconds_since_activity report))))
          (kill-buffer buffer))))))

(ert-deftest test-timvisher-agent-shell-recover-busy-with-dead-agent-is-wedged ()
  "A busy shell whose agent process is gone is wedged."
  (test-timvisher-agent-shell-recover--with-stubs 'busy
    (let* ((process (make-pipe-process :name "test-agent" :noquery t))
           (buffer (test-timvisher-agent-shell-recover--shell
                    "s1" :client `((:process . ,process))
                    :active-requests (list test-timvisher-agent-shell-recover--prompt)
                    :last-activity-time (current-time))))
      (delete-process process)
      (unwind-protect
          (let ((report (test-timvisher-agent-shell-recover--report "s1")))
            (should (eq t (alist-get 'wedged report)))
            (should (equal '("agent-process-dead") (alist-get 'reasons report))))
        (kill-buffer buffer)))))

(ert-deftest test-timvisher-agent-shell-recover-busy-without-prompt-request-is-wedged ()
  "Busy with no session/prompt request in flight is wedged."
  (test-timvisher-agent-shell-recover--with-stubs 'busy
    (test-timvisher-agent-shell-recover--with-process process
      (let ((buffer (test-timvisher-agent-shell-recover--shell
                     "s1" :client `((:process . ,process))
                     :active-requests '(((:method . "session/set_mode")))
                     :last-activity-time (current-time))))
        (unwind-protect
            (should (equal '("busy-without-prompt-request")
                           (alist-get 'reasons (test-timvisher-agent-shell-recover--report "s1"))))
          (kill-buffer buffer))))))

(ert-deftest test-timvisher-agent-shell-recover-busy-and-quiet-is-wedged ()
  "Busy and silent past the threshold with no tool running is wedged.

The threshold is tunable, and a finished tool call does not count as
running."
  (test-timvisher-agent-shell-recover--with-stubs 'busy
    (test-timvisher-agent-shell-recover--with-process process
      (let ((buffer (test-timvisher-agent-shell-recover--shell
                     "s1" :client `((:process . ,process))
                     :active-requests (list test-timvisher-agent-shell-recover--prompt)
                     :tool-calls '(("t1" . ((:status . "completed"))))
                     :last-activity-time (time-subtract nil 120))))
        (unwind-protect
            (progn
              (should (eq :false (alist-get 'wedged (test-timvisher-agent-shell-recover--report "s1"))))
              (let ((report (test-timvisher-agent-shell-recover--report "s1" 60)))
                (should (eq t (alist-get 'wedged report)))
                (should (string-match-p "\\`quiet-for-[0-9]+s-with-no-tool-running\\'"
                                        (car (alist-get 'reasons report))))))
          (kill-buffer buffer))))))

(ert-deftest test-timvisher-agent-shell-recover-quiet-with-a-tool-running-is-not-wedged ()
  "Silence while a tool call runs is a long tool call, however long."
  (test-timvisher-agent-shell-recover--with-stubs 'busy
    (test-timvisher-agent-shell-recover--with-process process
      (let ((buffer (test-timvisher-agent-shell-recover--shell
                     "s1" :client `((:process . ,process))
                     :active-requests (list test-timvisher-agent-shell-recover--prompt)
                     :tool-calls '(("t1" . ((:status . "in_progress"))))
                     :last-activity-time (time-subtract nil 100000))))
        (unwind-protect
            (let ((report (test-timvisher-agent-shell-recover--report "s1" 60)))
              (should (eq :false (alist-get 'wedged report)))
              (should (= 1 (alist-get 'running_tool_calls report))))
          (kill-buffer buffer))))))

(ert-deftest test-timvisher-agent-shell-recover-blocked-and-idle-shells-are-not-wedged ()
  "Waiting on a permission prompt, or idle with a dead agent, is not wedged."
  (dolist (status '(blocked ready))
    (test-timvisher-agent-shell-recover--with-stubs status
      (let ((buffer (test-timvisher-agent-shell-recover--shell
                     "s1" :last-activity-time (time-subtract nil 100000))))
        (unwind-protect
            (should (eq :false (alist-get 'wedged (test-timvisher-agent-shell-recover--report "s1" 60))))
          (kill-buffer buffer))))))

(ert-deftest test-timvisher-agent-shell-recover-report-no-buffer ()
  "An unknown session id reports no buffer."
  (test-timvisher-agent-shell-recover--with-stubs 'ready
    (should (equal "no buffer" (timvisher-agent-shell-wedge-report "nope")))))

(defmacro test-timvisher-agent-shell-recover--with-fork (supports-fork &rest body)
  "Run BODY around a recovery fork of shell \"old\" with fork stubbed.

SUPPORTS-FORK is the old shell's :supports-session-fork.  BODY sees
`old' (with two queued prompts), `new' (the shell the stubbed
`agent-shell--start' made, or nil), `handlers' (event to handler),
`inserted' (each insert's arguments), `delivered' (inserts and enqueues
in order, with the buffer each went to) and `started' (each start's
arguments)."
  (declare (indent 1))
  `(test-timvisher-agent-shell-recover--with-stubs 'ready
     (let* ((old (test-timvisher-agent-shell-recover--shell
                  "old" :supports-session-fork ,supports-fork :agent-config 'claude
                  :pending-prompts (list "queued one" "queued two")))
            (new nil) (handlers nil) (inserted nil) (started nil) (unsubscribed 0)
            (delivered nil)
            (timvisher-agent-shell--recoveries (make-hash-table :test #'equal)))
       (cl-letf (((symbol-function 'agent-shell--start)
                  (lambda (&rest args)
                    (push args started)
                    (setq new (test-timvisher-agent-shell-recover--shell "new"))))
                 ((symbol-function 'agent-shell-subscribe-to)
                  (lambda (&rest args)
                    (push (cons (plist-get args :event) (plist-get args :on-event)) handlers)
                    (plist-get args :event)))
                 ((symbol-function 'agent-shell-unsubscribe)
                  (lambda (&rest _) (cl-incf unsubscribed)))
                 ((symbol-function 'agent-shell--insert-to-shell-buffer)
                  (lambda (&rest args)
                    (push args inserted)
                    (setq delivered (append delivered (list (list 'insert (buffer-name (plist-get args :shell-buffer))))))))
                 ((symbol-function 'agent-shell--prompt-queue-enqueue)
                  (lambda (&rest args)
                    (setq delivered (append delivered (list (list 'enqueue (buffer-name) (plist-get args :prompt))))))))
         (unwind-protect (progn ,@body)
           (dolist (buffer (list old new))
             (when (buffer-live-p buffer) (kill-buffer buffer))))))))

(defun test-timvisher-agent-shell-recover--status (session-id)
  "Return SESSION-ID's recovery status parsed into an alist."
  (json-parse-string (timvisher-agent-shell-recover-status session-id)
                     :object-type 'alist :null-object nil))

(ert-deftest test-timvisher-agent-shell-recover-fork-recovers-once-ready ()
  "On prompt-ready the old shell dies, and the new one gets the note, then its queue."
  (let ((extra (make-temp-file "tvasr" nil nil "More context\n\n")))
    (unwind-protect
        (test-timvisher-agent-shell-recover--with-fork t
          (let ((first (json-parse-string (timvisher-agent-shell-recover-fork "old" extra)
                                          :object-type 'alist :null-object nil)))
            (should (equal "forking" (alist-get 'status first)))
            (should (equal "shell-new" (alist-get 'new_buffer first))))
          (should (equal '(:config claude :session-strategy new :fork-session-id "old"
                           :new-session t :no-focus t)
                         (car started)))
          (should (buffer-live-p old))
          (funcall (alist-get 'prompt-ready handlers) '((:event . prompt-ready)))
          (should-not (buffer-live-p old))
          (should (= 2 unsubscribed))
          (let ((insert (car inserted)))
            (should (eq new (plist-get insert :shell-buffer)))
            (should (eq t (plist-get insert :submit)))
            (should (string-match-p "recovery fork of session old (shell-old)" (plist-get insert :text)))
            (should (string-match-p "Its 2 queued prompts follow this note" (plist-get insert :text)))
            (should (string-suffix-p "\n\nMore context" (plist-get insert :text))))
          (should (equal '((insert "shell-new")
                           (enqueue "shell-new" "queued one")
                           (enqueue "shell-new" "queued two"))
                         delivered))
          (let ((status (test-timvisher-agent-shell-recover--status "old")))
            (should (equal "recovered" (alist-get 'status status)))
            (should (equal "new" (alist-get 'new_session_id status)))
            (should (= 2 (alist-get 'forwarded_prompts status)))))
      (delete-file extra))))

(ert-deftest test-timvisher-agent-shell-recover-note-counts-the-forwarded-queue ()
  "The note mentions forwarded prompts only when there are some, in good English."
  (should-not (string-match-p "queued" (timvisher-agent-shell--recovery-note "o" "b" 0 nil)))
  (should (string-match-p "Its 1 queued prompt follows this note"
                          (timvisher-agent-shell--recovery-note "o" "b" 1 nil)))
  (should (string-match-p "Its 3 queued prompts follow this note"
                          (timvisher-agent-shell--recovery-note "o" "b" 3 nil))))

(ert-deftest test-timvisher-agent-shell-recover-fork-keeps-the-old-shell-on-error ()
  "A fork error leaves the old shell alone and records the failure."
  (test-timvisher-agent-shell-recover--with-fork t
    (timvisher-agent-shell-recover-fork "old")
    (funcall (alist-get 'error handlers) '((:event . error) (:data . "boom")))
    (should (buffer-live-p old))
    (should-not delivered)
    (let ((status (test-timvisher-agent-shell-recover--status "old")))
      (should (equal "failed" (alist-get 'status status)))
      (should (string-match-p "boom" (alist-get 'error status))))))

(ert-deftest test-timvisher-agent-shell-recover-fork-needs-fork-support ()
  "An agent without session forking fails without starting anything."
  (test-timvisher-agent-shell-recover--with-fork nil
    (should (equal "failed"
                   (alist-get 'status (json-parse-string (timvisher-agent-shell-recover-fork "old")
                                                         :object-type 'alist))))
    (should-not started)
    (should (buffer-live-p old))))

(ert-deftest test-timvisher-agent-shell-recover-fork-no-buffer ()
  "An unknown session id starts nothing."
  (test-timvisher-agent-shell-recover--with-fork t
    (should (equal "no buffer" (timvisher-agent-shell-recover-fork "nope")))
    (should-not started)
    (should (equal "no recovery" (timvisher-agent-shell-recover-status "nope")))))

(provide 'timvisher-agent-shell-recover-test)
;;; timvisher-agent-shell-recover-test.el ends here
