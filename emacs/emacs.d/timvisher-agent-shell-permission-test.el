;;; timvisher-agent-shell-permission-test.el --- Tests for timvisher-agent-shell-permission -*- lexical-binding: t; -*-

;;; Commentary:
;; Showing, answering and cancelling against a fake shell whose state
;; holds pending permission requests.  agent-shell's response and
;; interrupt entry points are stubbed, so no agent runs; each test runs
;; the timers the helpers schedule by hand.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'timvisher-agent-shell-permission)

(defun test-timvisher-agent-shell-permission--actions ()
  "Return the actions agent-shell makes for a usual Claude prompt."
  '(((:label . "Allow (y)") (:option . "Allow") (:char . "y")
     (:kind . "allow_once") (:option-id . "default"))
    ((:label . "Reject (C-c C-c)") (:option . "Reject") (:char . "C-c C-c")
     (:kind . "reject_once") (:option-id . "reject"))
    ((:label . "Always Allow (!)") (:option . "Always Allow") (:char . "!")
     (:kind . "allow_always") (:option-id . "acceptEdits"))))

(defmacro test-timvisher-agent-shell-permission--with-shell (tool-calls &rest body)
  "Run BODY with a fake shell, session \"s1\", holding TOOL-CALLS.

BODY sees `shell', its `state', `status' (what `agent-shell-status'
returns; setq it), `calls' (each stubbed entry point's arguments,
oldest first) and `timers' (what `run-at-time' was asked to run,
oldest first, each (FUNCTION . ARGS))."
  (declare (indent 1))
  `(let* ((shell (generate-new-buffer "shell-s1"))
          (state (list (cons :session (list (cons :id "s1")))
                       (cons :client 'fake-client)
                       (cons :tool-calls ,tool-calls)))
          (status 'blocked)
          (calls nil)
          (timers nil))
     (clrhash timvisher-agent-shell--operations)
     (unwind-protect
         (cl-letf (((symbol-function 'agent-shell-buffers)
                    (lambda () (list shell)))
                   ((symbol-function 'agent-shell--state)
                    (lambda () (and (eq (current-buffer) shell) state)))
                   ((symbol-function 'agent-shell-status)
                    (lambda (&rest _) status))
                   ((symbol-function 'agent-shell--permission-title)
                    (lambda (&key tool-call) (concat "title: " (map-elt tool-call :title))))
                   ((symbol-function 'run-at-time)
                    (lambda (_time _repeat function &rest args)
                      (setq timers (append timers (list (cons function args))))))
                   ((symbol-function 'agent-shell--send-permission-response)
                    (lambda (&rest args)
                      (setq calls (append calls (list (cons 'respond args))))
                      (let ((entry (assoc (plist-get args :tool-call-id) (map-elt state :tool-calls))))
                        (setcdr entry (map-delete (cdr entry) :permission-request-id)))))
                   ((symbol-function 'agent-shell-interrupt)
                    (lambda (&rest args)
                      (setq calls (append calls (list (cons 'interrupt args)))))))
           ,@body)
       (kill-buffer shell))))

(defun test-timvisher-agent-shell-permission--pending (id request-id title)
  "Return a pending tool call ID with REQUEST-ID and TITLE."
  (list id
        (cons :title title)
        (cons :kind "execute")
        (cons :permission-request-id request-id)
        (cons :permission-actions (test-timvisher-agent-shell-permission--actions))))

(defun test-timvisher-agent-shell-permission--two-pending ()
  "Return tool calls with two pending prompts (latest first) and an answered one."
  (list (test-timvisher-agent-shell-permission--pending "tc-new" 7 "rm -rf build")
        (list "tc-done" (cons :title "ls") (cons :status "completed"))
        (test-timvisher-agent-shell-permission--pending "tc-old" 3 "make")))

(defun test-timvisher-agent-shell-permission--parse (json)
  "Parse JSON into an alist with symbol keys."
  (json-parse-string json :object-type 'alist :null-object nil :false-object nil))

(defmacro test-timvisher-agent-shell-permission--run-timers ()
  "Run and forget the timers the helpers scheduled, in `timers'."
  '(let ((pending timers))
     (setq timers nil)
     (dolist (timer pending)
       (apply (car timer) (cdr timer)))))

(ert-deftest test-timvisher-agent-shell-permission-prompt-shows-the-latest ()
  "The latest pending prompt is shown with its title and options."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (let* ((report (test-timvisher-agent-shell-permission--parse
                    (timvisher-agent-shell-permission-prompt "s1")))
           (prompt (alist-get 'prompt report)))
      (should (equal "blocked" (alist-get 'status report)))
      (should (equal 2 (alist-get 'pending_count report)))
      (should (equal "tc-new" (alist-get 'tool_call_id prompt)))
      (should (equal 7 (alist-get 'request_id prompt)))
      (should (equal "title: rm -rf build" (alist-get 'title prompt)))
      (should (equal '("allow_once" "reject_once" "allow_always")
                     (mapcar (lambda (o) (alist-get 'kind o)) (alist-get 'options prompt))))
      (should (equal "acceptEdits" (alist-get 'option_id (aref (alist-get 'options prompt) 2)))))))

(ert-deftest test-timvisher-agent-shell-permission-prompt-none-pending ()
  "A shell with nothing pending shows a null prompt."
  (test-timvisher-agent-shell-permission--with-shell
      (list (list "tc-done" (cons :title "ls") (cons :status "completed")))
    (setq status 'busy)
    (let ((report (test-timvisher-agent-shell-permission--parse
                   (timvisher-agent-shell-permission-prompt "s1"))))
      (should (equal 0 (alist-get 'pending_count report)))
      (should-not (alist-get 'prompt report)))))

(ert-deftest test-timvisher-agent-shell-permission-no-buffer ()
  "An unknown session id reports no buffer and schedules nothing."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (should (equal "no buffer" (timvisher-agent-shell-permission-prompt "nope")))
    (should (equal "no buffer" (timvisher-agent-shell-permission-answer "nope" "allow_once")))
    (should (equal "no buffer" (timvisher-agent-shell-turn-cancel "nope")))
    (should (equal "no buffer" (timvisher-agent-shell-operation-status "nope")))
    (should-not timers)))

(ert-deftest test-timvisher-agent-shell-permission-approve-answers-from-a-timer ()
  "Approving schedules the answer instead of sending it, then sends allow_once to the latest prompt."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (let ((report (test-timvisher-agent-shell-permission--parse
                   (timvisher-agent-shell-permission-answer "s1" "allow_once"))))
      (should (equal "scheduled" (alist-get 'outcome report)))
      (should (equal "default" (alist-get 'option_id report)))
      (should-not calls)
      (should (= 1 (length timers)))
      (test-timvisher-agent-shell-permission--run-timers)
      (should (equal '((respond :client fake-client :request-id 7 :option-id "default"
                                :state nil :tool-call-id "tc-new" :message-text "Allow"))
                     (mapcar (lambda (call) (cons (car call) (plist-put (copy-sequence (cdr call)) :state nil)))
                             calls)))
      (let ((after (test-timvisher-agent-shell-permission--parse
                    (timvisher-agent-shell-operation-status "s1"))))
        (should (equal "answered" (alist-get 'outcome (alist-get 'operation after))))
        (should (eq t (alist-get 'answered after)))
        (should (equal "tc-old" (alist-get 'tool_call_id (alist-get 'prompt after))))))))

(ert-deftest test-timvisher-agent-shell-permission-approve-always ()
  "Approving always sends the allow_always option and does not interrupt."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (timvisher-agent-shell-permission-answer "s1" "allow_always")
    (test-timvisher-agent-shell-permission--run-timers)
    (should (equal '(respond) (mapcar #'car calls)))
    (should (equal "acceptEdits" (plist-get (cdar calls) :option-id)))))

(ert-deftest test-timvisher-agent-shell-permission-deny-rejects-and-interrupts ()
  "Denying sends reject_once and then interrupts with force, as the row's key does."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (timvisher-agent-shell-permission-answer "s1" "reject_once")
    (should-not calls)
    (test-timvisher-agent-shell-permission--run-timers)
    (should (equal '(respond interrupt) (mapcar #'car calls)))
    (should (equal "reject" (plist-get (cdar calls) :option-id)))
    (should (equal '(interrupt t) (cadr calls)))))

(ert-deftest test-timvisher-agent-shell-permission-answer-no-prompt ()
  "Answering with nothing pending reports no_prompt and schedules nothing."
  (test-timvisher-agent-shell-permission--with-shell nil
    (setq status 'busy)
    (should (equal "no_prompt"
                   (alist-get 'outcome (test-timvisher-agent-shell-permission--parse
                                        (timvisher-agent-shell-permission-answer "s1" "allow_once")))))
    (should-not timers)))

(ert-deftest test-timvisher-agent-shell-permission-answer-no-such-option ()
  "Answering with a kind the prompt does not offer reports no_such_option with the prompt's options."
  (test-timvisher-agent-shell-permission--with-shell
      (list (list "tc" (cons :title "edit") (cons :permission-request-id 1)
                  (cons :permission-actions (seq-take (test-timvisher-agent-shell-permission--actions) 2))))
    (let ((report (test-timvisher-agent-shell-permission--parse
                   (timvisher-agent-shell-permission-answer "s1" "allow_always"))))
      (should (equal "no_such_option" (alist-get 'outcome report)))
      (should (= 2 (length (alist-get 'options (alist-get 'prompt report))))))
    (should-not timers)))

(ert-deftest test-timvisher-agent-shell-permission-answered-in-the-meantime ()
  "A prompt answered between scheduling and the timer is left alone."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (timvisher-agent-shell-permission-answer "s1" "allow_once")
    (let ((entry (assoc "tc-new" (map-elt state :tool-calls))))
      (setcdr entry (map-delete (cdr entry) :permission-request-id)))
    (test-timvisher-agent-shell-permission--run-timers)
    (should-not calls)
    (should (equal "already_answered"
                   (alist-get 'outcome (alist-get 'operation (test-timvisher-agent-shell-permission--parse
                                                              (timvisher-agent-shell-operation-status "s1"))))))))

(ert-deftest test-timvisher-agent-shell-permission-answer-failure-is-recorded ()
  "An error while answering is recorded instead of escaping the timer."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (timvisher-agent-shell-permission-answer "s1" "allow_once")
    (cl-letf (((symbol-function 'agent-shell--send-permission-response)
               (lambda (&rest _) (error "Client gone"))))
      (test-timvisher-agent-shell-permission--run-timers))
    (let ((operation (alist-get 'operation (test-timvisher-agent-shell-permission--parse
                                            (timvisher-agent-shell-operation-status "s1")))))
      (should (equal "failed" (alist-get 'outcome operation)))
      (should (equal "Client gone" (alist-get 'error operation))))))

(ert-deftest test-timvisher-agent-shell-turn-cancel-interrupts-from-a-timer ()
  "Cancelling a busy turn schedules a forced interrupt instead of running it."
  (test-timvisher-agent-shell-permission--with-shell nil
    (setq status 'busy)
    (should (equal "scheduled"
                   (alist-get 'outcome (test-timvisher-agent-shell-permission--parse
                                        (timvisher-agent-shell-turn-cancel "s1")))))
    (should-not calls)
    (test-timvisher-agent-shell-permission--run-timers)
    (should (equal '((interrupt t)) calls))
    (should (equal "cancelled"
                   (alist-get 'outcome (alist-get 'operation (test-timvisher-agent-shell-permission--parse
                                                              (timvisher-agent-shell-operation-status "s1"))))))))

(ert-deftest test-timvisher-agent-shell-turn-cancel-idle-is-a-no-op ()
  "Cancelling with no turn running reports idle and does nothing."
  (test-timvisher-agent-shell-permission--with-shell nil
    (setq status 'ready)
    (should (equal "idle"
                   (alist-get 'outcome (test-timvisher-agent-shell-permission--parse
                                        (timvisher-agent-shell-turn-cancel "s1")))))
    (should-not timers)))

(ert-deftest test-timvisher-agent-shell-permission-summary ()
  "The summary is the latest pending prompt's title, or :null."
  (test-timvisher-agent-shell-permission--with-shell (test-timvisher-agent-shell-permission--two-pending)
    (with-current-buffer shell
      (should (equal "title: rm -rf build" (timvisher-agent-shell-permission-summary)))
      (setf (map-elt state :tool-calls) nil)
      (should (eq :null (timvisher-agent-shell-permission-summary))))))

(provide 'timvisher-agent-shell-permission-test)
;;; timvisher-agent-shell-permission-test.el ends here
