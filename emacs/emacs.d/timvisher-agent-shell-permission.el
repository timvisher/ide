;;; timvisher-agent-shell-permission.el --- Answer permission prompts and cancel turns by session id -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Lets something outside Emacs (another agent, through emacsclient)
;; see an agent-shell's pending permission prompt, answer it, or cancel
;; its running turn, for `timvisher_emacs agent-shell permission-prompt'
;; and `agent-shell turn cancel'.
;;
;; Every answer and cancel runs from a timer, never inside the server
;; eval that asks for it, so the eval returns at once and the server is
;; never left waiting on agent-shell.  Poll
;; `timvisher-agent-shell-operation-status' for the outcome.

;;; Code:

(require 'map)
(require 'seq)
(require 'subr-x)
(require 'timvisher-agent-shell-send)

(declare-function agent-shell--state "agent-shell")
(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell-interrupt "agent-shell")
(declare-function agent-shell--send-permission-response "agent-shell")
(declare-function agent-shell--permission-title "agent-shell")

(defvar timvisher-agent-shell--operations (make-hash-table :test #'equal)
  "The latest answer or cancel by session id, each an alist of what happened.")

(defun timvisher-agent-shell--pending-permission ()
  "Return the current shell's latest pending permission prompt, or nil.

The value is (TOOL-CALL-ID . TOOL-CALL).  agent-shell adds each new
tool call at the head of its :tool-calls alist, so the first pending
one is the latest."
  (seq-find (lambda (entry)
              (map-elt (cdr entry) :permission-request-id))
            (map-elt (agent-shell--state) :tool-calls)))

(defun timvisher-agent-shell--permission-title (tool-call)
  "Return TOOL-CALL's permission title as agent-shell shows it, or nil."
  (when-let* ((title (or (ignore-errors (agent-shell--permission-title :tool-call tool-call))
                         (map-elt tool-call :title))))
    (substring-no-properties title)))

(defun timvisher-agent-shell--permission-alist (entry)
  "Return the pending permission prompt ENTRY as an alist for JSON."
  (let ((tool-call (cdr entry)))
    `((tool_call_id . ,(car entry))
      (request_id . ,(map-elt tool-call :permission-request-id))
      (title . ,(or (timvisher-agent-shell--permission-title tool-call) :null))
      (tool_kind . ,(or (map-elt tool-call :kind) :null))
      (options . ,(vconcat
                   (mapcar (lambda (action)
                             `((kind . ,(map-elt action :kind))
                               (name . ,(or (map-elt action :option) :null))
                               (option_id . ,(map-elt action :option-id))))
                           (map-elt tool-call :permission-actions)))))))

(defun timvisher-agent-shell-permission-summary ()
  "Return the current shell's latest pending prompt's title, or :null.

For `timvisher_emacs agent-shell ls'."
  (if-let* ((entry (timvisher-agent-shell--pending-permission)))
      (or (timvisher-agent-shell--permission-title (cdr entry)) "")
    :null))

(defun timvisher-agent-shell--shell-alist (session-id)
  "Return the current shell's identity and status as an alist for JSON."
  `((session_id . ,session-id)
    (buffer . ,(buffer-name))
    (status . ,(symbol-name (agent-shell-status)))))

(defun timvisher-agent-shell-permission-prompt (session-id)
  "Return the latest pending permission prompt of SESSION-ID's shell as JSON.

Its .prompt is null when nothing is pending.  Return \"no buffer\" when
no live agent-shell has SESSION-ID."
  (if-let* ((buffer (timvisher-agent-shell-send-buffer session-id)))
      (with-current-buffer buffer
        (let ((entry (timvisher-agent-shell--pending-permission)))
          (json-serialize
           (append (timvisher-agent-shell--shell-alist session-id)
                   `((pending_count . ,(seq-count (lambda (e) (map-elt (cdr e) :permission-request-id))
                                                  (map-elt (agent-shell--state) :tool-calls)))
                     (prompt . ,(if entry (timvisher-agent-shell--permission-alist entry) :null)))))))
    "no buffer"))

(defun timvisher-agent-shell--record (session-id &rest fields)
  "Merge FIELDS (alternating keys and values) into SESSION-ID's operation."
  (let ((record (gethash session-id timvisher-agent-shell--operations)))
    (while fields
      (setf (alist-get (pop fields) record) (pop fields)))
    (puthash session-id record timvisher-agent-shell--operations)))

(defun timvisher-agent-shell--answer-now (buffer session-id tool-call-id request-id action)
  "Answer REQUEST-ID of TOOL-CALL-ID in BUFFER with ACTION, as its row's key does.

Runs from a timer.  Does nothing when the request is no longer pending,
for someone may have answered it since it was scheduled."
  (condition-case err
      (if (not (buffer-live-p buffer))
          (timvisher-agent-shell--record session-id 'outcome "failed" 'error "the shell was killed")
        (with-current-buffer buffer
          (let ((state (agent-shell--state)))
            (if (not (equal request-id
                            (map-nested-elt state (list :tool-calls tool-call-id :permission-request-id))))
                (timvisher-agent-shell--record session-id 'outcome "already_answered")
              ;; agent-shell's own response path rather than the row's
              ;; keymap or button: the binding is the same call, and
              ;; call-interactively of a button from a server eval has
              ;; locked an Emacs.
              (agent-shell--send-permission-response
               :client (map-elt state :client)
               :request-id request-id
               :option-id (map-elt action :option-id)
               :state state
               :tool-call-id tool-call-id
               :message-text (map-elt action :option))
              (when (equal (map-elt action :kind) "reject_once")
                (agent-shell-interrupt t))
              (timvisher-agent-shell--record session-id 'outcome "answered")))))
    (error
     (timvisher-agent-shell--record session-id 'outcome "failed" 'error (error-message-string err)))))

(defun timvisher-agent-shell-permission-answer (session-id kind)
  "Answer the latest pending permission prompt of SESSION-ID's shell.

KIND is the ACP option kind to choose: \"allow_once\", \"allow_always\"
or \"reject_once\".  Rejecting also interrupts the turn, as the row's
reject key does.  The answer is sent from a timer; return JSON whose
.outcome is \"scheduled\", or \"no_prompt\" when nothing is pending, or
\"no_such_option\" when the prompt offers no option of KIND.  Return
\"no buffer\" when no live agent-shell has SESSION-ID."
  (if-let* ((buffer (timvisher-agent-shell-send-buffer session-id)))
      (with-current-buffer buffer
        (let* ((entry (timvisher-agent-shell--pending-permission))
               (action (and entry
                            (seq-find (lambda (a) (equal kind (map-elt a :kind)))
                                      (map-elt (cdr entry) :permission-actions))))
               (outcome (cond ((not entry) "no_prompt")
                              ((not action) "no_such_option")
                              (t "scheduled"))))
          (when action
            (let ((tool-call-id (car entry))
                  (request-id (map-elt (cdr entry) :permission-request-id)))
              (puthash session-id nil timvisher-agent-shell--operations)
              (timvisher-agent-shell--record
               session-id 'operation "answer" 'kind kind 'outcome outcome
               'tool_call_id tool-call-id 'request_id request-id)
              (run-at-time 0 nil #'timvisher-agent-shell--answer-now
                           buffer session-id tool-call-id request-id action)))
          (json-serialize
           (append (timvisher-agent-shell--shell-alist session-id)
                   `((outcome . ,outcome)
                     (kind . ,kind)
                     (option_id . ,(or (map-elt action :option-id) :null))
                     (prompt . ,(if entry (timvisher-agent-shell--permission-alist entry) :null)))))))
    "no buffer"))

(defun timvisher-agent-shell--cancel-now (buffer session-id)
  "Interrupt BUFFER's running turn, as its interrupt key does with force.

Runs from a timer."
  (condition-case err
      (if (not (buffer-live-p buffer))
          (timvisher-agent-shell--record session-id 'outcome "failed" 'error "the shell was killed")
        (with-current-buffer buffer
          (agent-shell-interrupt t)
          (timvisher-agent-shell--record session-id 'outcome "cancelled")))
    (error
     (timvisher-agent-shell--record session-id 'outcome "failed" 'error (error-message-string err)))))

(defun timvisher-agent-shell-turn-cancel (session-id)
  "Cancel the running turn of SESSION-ID's shell.

The cancel is sent from a timer; return JSON whose .outcome is
\"scheduled\", or \"idle\" when no turn is running and nothing is done.
Return \"no buffer\" when no live agent-shell has SESSION-ID."
  (if-let* ((buffer (timvisher-agent-shell-send-buffer session-id)))
      (with-current-buffer buffer
        (let ((outcome (if (eq 'ready (agent-shell-status)) "idle" "scheduled")))
          (when (equal outcome "scheduled")
            (puthash session-id nil timvisher-agent-shell--operations)
            (timvisher-agent-shell--record session-id 'operation "cancel" 'outcome outcome)
            (run-at-time 0 nil #'timvisher-agent-shell--cancel-now buffer session-id))
          (json-serialize
           (append (timvisher-agent-shell--shell-alist session-id)
                   `((outcome . ,outcome))))))
    "no buffer"))

(defun timvisher-agent-shell-operation-status (session-id)
  "Return SESSION-ID's shell and its latest answer or cancel as JSON.

.operation is what `timvisher-agent-shell-permission-answer' or
`timvisher-agent-shell-turn-cancel' scheduled and how it went, and
.answered says whether the answered request is no longer pending.
Return \"no buffer\" when no live agent-shell has SESSION-ID."
  (if-let* ((buffer (timvisher-agent-shell-send-buffer session-id)))
      (with-current-buffer buffer
        (let* ((record (gethash session-id timvisher-agent-shell--operations))
               (entry (timvisher-agent-shell--pending-permission))
               (answered (and (alist-get 'request_id record)
                              (not (equal (alist-get 'request_id record)
                                          (map-nested-elt (agent-shell--state)
                                                          (list :tool-calls (alist-get 'tool_call_id record)
                                                                :permission-request-id)))))))
          (json-serialize
           (append (timvisher-agent-shell--shell-alist session-id)
                   `((operation . ,(or (copy-alist record) :null))
                     (answered . ,(if answered t :false))
                     (prompt . ,(if entry (timvisher-agent-shell--permission-alist entry) :null)))))))
    "no buffer"))

(provide 'timvisher-agent-shell-permission)
;;; timvisher-agent-shell-permission.el ends here
