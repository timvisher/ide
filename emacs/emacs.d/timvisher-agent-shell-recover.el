;;; timvisher-agent-shell-recover.el --- Detect and recover wedged agent-shells -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `timvisher-agent-shell-wedge-report' judges whether the agent-shell
;; with a session id is wedged; `timvisher-agent-shell-recover-fork'
;; forks it into a new shell, kills the old one once the new one is
;; ready, and tells the new one it is a recovery fork.  Both return
;; JSON strings for `timvisher_emacs session is-wedged' and `session
;; recover fork'.

;;; Code:

(require 'map)
(require 'seq)
(require 'subr-x)
(require 'timvisher-agent-shell-send)

(declare-function agent-shell--state "agent-shell")
(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell--start "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell-unsubscribe "agent-shell")
(declare-function agent-shell--insert-to-shell-buffer "agent-shell")

(defvar shell-maker-prompt-before-killing-buffer)

(defcustom timvisher-agent-shell-wedge-quiet-seconds 300
  "Seconds a busy shell with no tool running may be silent before it is wedged.

Thinking streams thought chunks, which count as activity, so silence
with nothing running is the agent not answering.  Silence while a tool
call runs is a long tool call (a test suite, a subagent) and never
counts."
  :type 'integer
  :group 'agent-shell)

(defun timvisher-agent-shell--wedge-signals (quiet-seconds)
  "Return the wedge facts about the current agent-shell as an alist.

QUIET-SECONDS is how long a busy shell may be silent."
  (let* ((state (agent-shell--state))
         (status (agent-shell-status))
         (busy (memq status '(busy blocked)))
         (process (map-nested-elt state '(:client :process)))
         (process-live (and process (process-live-p process) t))
         (last-activity (map-elt state :last-activity-time))
         (quiet (and last-activity
                     (truncate (float-time (time-subtract nil last-activity)))))
         (prompt-in-flight (and (seq-find (lambda (request)
                                            (equal "session/prompt" (map-elt request :method)))
                                          (map-elt state :active-requests))
                                t))
         (running-tool-calls (seq-count (lambda (entry)
                                          (not (member (map-elt (cdr entry) :status)
                                                       '("completed" "failed"))))
                                        (map-elt state :tool-calls)))
         (reasons
          (when (eq status 'busy)
            (delq nil
                  (list (unless process-live "agent-process-dead")
                        (unless prompt-in-flight "busy-without-prompt-request")
                        (when (and quiet (<= quiet-seconds quiet) (zerop running-tool-calls))
                          (format "quiet-for-%ds-with-no-tool-running" quiet)))))))
    `((session_id . ,(map-nested-elt state '(:session :id)))
      (buffer . ,(buffer-name))
      (status . ,(symbol-name status))
      (busy . ,(if busy t :false))
      (agent_process_live . ,(if process-live t :false))
      (prompt_in_flight . ,(if prompt-in-flight t :false))
      (seconds_since_activity . ,(or quiet :null))
      (running_tool_calls . ,running-tool-calls)
      (pending_prompts . ,(length (map-elt state :pending-prompts)))
      (quiet_seconds_threshold . ,quiet-seconds)
      (wedged . ,(if reasons t :false))
      (reasons . ,(vconcat reasons)))))

(defun timvisher-agent-shell-wedge-report (session-id &optional quiet-seconds)
  "Return a JSON report on whether the agent-shell with SESSION-ID is wedged.

A shell is wedged when it is busy (not blocked on a permission request)
and its agent process is dead, it has no session/prompt request in
flight, or the agent has been silent for QUIET-SECONDS (default
`timvisher-agent-shell-wedge-quiet-seconds') with no tool call
running.  Return \"no buffer\"
when no live agent-shell has SESSION-ID."
  (if-let* ((buffer (timvisher-agent-shell-send-buffer session-id)))
      (with-current-buffer buffer
        (json-serialize
         (timvisher-agent-shell--wedge-signals
          (or quiet-seconds timvisher-agent-shell-wedge-quiet-seconds))))
    "no buffer"))

(defvar timvisher-agent-shell--recoveries (make-hash-table :test #'equal)
  "Recovery forks by the old session id, each an alist of what happened.")

(defun timvisher-agent-shell--recovery-note (old-session-id old-buffer-name extra)
  "Return the note telling a recovery fork what it is.

OLD-SESSION-ID and OLD-BUFFER-NAME name the wedged shell; EXTRA, when
non-nil, is appended."
  (concat
   (format "From timvisher_emacs session recover fork: this session is a recovery fork of session %s (%s), which was wedged and has been killed. Its conversation is yours; continue its work. Anything it had running (commands, tool calls, half-made edits) may not have finished, so check that state before building on it."
           old-session-id old-buffer-name)
   (when extra (concat "\n\n" extra))))

(defun timvisher-agent-shell--recovery-record (old-session-id &rest fields)
  "Merge FIELDS (alternating keys and values) into OLD-SESSION-ID's recovery."
  (let ((record (gethash old-session-id timvisher-agent-shell--recoveries)))
    (while fields
      (setf (alist-get (pop fields) record) (pop fields)))
    (puthash old-session-id record timvisher-agent-shell--recoveries)))

(defun timvisher-agent-shell-recover-status (old-session-id)
  "Return OLD-SESSION-ID's recovery fork as JSON, or \"no recovery\"."
  (if-let* ((record (gethash old-session-id timvisher-agent-shell--recoveries)))
      (let* ((new (get-buffer (or (alist-get 'new_buffer record) "")))
             (new-session-id (or (alist-get 'new_session_id record)
                                 (and new
                                      (with-current-buffer new
                                    (map-nested-elt (agent-shell--state) '(:session :id)))))))
        (json-serialize
         (cons (cons 'new_session_id (or new-session-id :null))
               (assq-delete-all 'new_session_id (copy-alist record)))))
    "no recovery"))

(defun timvisher-agent-shell-recover-fork (session-id &optional message-file)
  "Fork the agent-shell with SESSION-ID to recover it, and return its status.

The fork starts a new agent and forks the session from the agent's own
copy, so it does not need the old agent to answer.  When the new shell
is ready, the old shell is killed and the new one is sent a note that it
is a recovery fork, followed by MESSAGE-FILE's contents when given.
Poll `timvisher-agent-shell-recover-status' for the outcome.  Return
\"no buffer\" when no live agent-shell has SESSION-ID."
  (if-let* ((old (timvisher-agent-shell-send-buffer session-id)))
      (let* ((state (with-current-buffer old (agent-shell--state)))
             (old-name (buffer-name old))
             (extra (when message-file
                      (with-temp-buffer
                        (insert-file-contents message-file)
                        (string-trim-right (buffer-string))))))
        (puthash session-id nil timvisher-agent-shell--recoveries)
        (timvisher-agent-shell--recovery-record
         session-id 'old_session_id session-id 'old_buffer old-name 'status "forking")
        (if (not (map-elt state :supports-session-fork))
            (timvisher-agent-shell--recovery-record
             session-id 'status "failed" 'error "the agent does not support session forking")
          ;; agent-shell--start rather than agent-shell-fork: the command
          ;; only works on the current buffer and returns what displaying
          ;; the new shell returns, not the new shell.
          (let* ((new (with-current-buffer old
                        (agent-shell--start
                         :config (map-elt state :agent-config)
                         :session-strategy 'new
                         :fork-session-id session-id
                         :new-session t
                         :no-focus t)))
                 (subscriptions nil)
                 (finish
                  (lambda (outcome &optional error-message)
                    (mapc (lambda (subscription)
                            (agent-shell-unsubscribe :subscription subscription))
                          subscriptions)
                    (if (eq outcome 'ready)
                        (let ((new-session-id
                               (with-current-buffer new
                                 (map-nested-elt (agent-shell--state) '(:session :id)))))
                          (when (buffer-live-p old)
                            (let ((shell-maker-prompt-before-killing-buffer nil))
                              (kill-buffer old)))
                          (agent-shell--insert-to-shell-buffer
                           :shell-buffer new
                           :text (timvisher-agent-shell--recovery-note session-id old-name extra)
                           :submit t
                           :no-focus t)
                          (timvisher-agent-shell--recovery-record
                           session-id 'status "recovered" 'new_session_id new-session-id))
                      (timvisher-agent-shell--recovery-record
                       session-id 'status "failed" 'error (or error-message "the fork failed"))))))
            (timvisher-agent-shell--recovery-record session-id 'new_buffer (buffer-name new))
            (setq subscriptions
                  (list (agent-shell-subscribe-to
                         :shell-buffer new :event 'prompt-ready
                         :on-event (lambda (_event) (funcall finish 'ready)))
                        (agent-shell-subscribe-to
                         :shell-buffer new :event 'error
                         :on-event (lambda (event)
                                     (funcall finish 'failed
                                              (format "%S" (map-elt event :data)))))))))
        (timvisher-agent-shell-recover-status session-id))
    "no buffer"))

(provide 'timvisher-agent-shell-recover)
;;; timvisher-agent-shell-recover.el ends here
