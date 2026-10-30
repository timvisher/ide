;;; timvisher-agent-shell-send-test.el --- Tests for timvisher-agent-shell-send -*- lexical-binding: t; -*-

;;; Commentary:
;; Finding a shell by session id, and queueing versus submitting.  The
;; agent-shell entry points are stubbed, so no agent runs.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'timvisher-agent-shell-send)

(defmacro test-timvisher-agent-shell-send--with-shells (busy &rest body)
  "Run BODY with two fake shells, sessions \"s1\" and \"s2\".

BUSY says whether `shell-maker-busy' reports the shells busy.  BODY sees
`shells' (an alist of session id to buffer) and `calls' (each stubbed
entry point's buffer name and arguments, oldest first)."
  (declare (indent 1))
  `(let* ((shells (mapcar (lambda (sid)
                            (cons sid (generate-new-buffer (concat "shell-" sid))))
                          '("s1" "s2")))
          (calls nil))
     (unwind-protect
         (cl-letf (((symbol-function 'agent-shell-buffers)
                    (lambda () (mapcar #'cdr shells)))
                   ((symbol-function 'agent-shell--state)
                    (lambda ()
                      `((:session . ((:id . ,(car (rassq (current-buffer) shells))))))))
                   ((symbol-function 'shell-maker-busy)
                    (lambda () ,busy))
                   ((symbol-function 'agent-shell--prompt-queue-enqueue)
                    (lambda (&rest args)
                      (setq calls (append calls (list (cons (buffer-name) (cons 'enqueue args)))))))
                   ((symbol-function 'agent-shell--insert-to-shell-buffer)
                    (lambda (&rest args)
                      (setq calls (append calls (list (cons (buffer-name) (cons 'insert args))))))))
           ,@body)
       (mapc (lambda (shell) (kill-buffer (cdr shell))) shells))))

(ert-deftest test-timvisher-agent-shell-send-buffer-finds-by-session-id ()
  "The shell is the one whose session id matches, not the first one."
  (test-timvisher-agent-shell-send--with-shells nil
    (should (eq (cdr (assoc "s2" shells))
                (timvisher-agent-shell-send-buffer "s2")))
    (should-not (timvisher-agent-shell-send-buffer "nope"))))

(ert-deftest test-timvisher-agent-shell-send-text-submits-to-an-idle-shell ()
  "An idle shell gets the text submitted without taking focus."
  (test-timvisher-agent-shell-send--with-shells nil
    (should (equal "submitted" (timvisher-agent-shell-send-text "s2" "hello")))
    (should (equal `(("shell-s2" insert :shell-buffer ,(cdr (assoc "s2" shells))
                      :text "hello" :submit t :no-focus t))
                   calls))))

(ert-deftest test-timvisher-agent-shell-send-text-queues-in-a-busy-shell ()
  "A busy shell gets the text queued and nothing submitted."
  (test-timvisher-agent-shell-send--with-shells t
    (should (equal "queued" (timvisher-agent-shell-send-text "s1" "hello")))
    (should (equal '(("shell-s1" enqueue :prompt "hello")) calls))))

(ert-deftest test-timvisher-agent-shell-send-text-no-buffer ()
  "An unknown session id touches no shell."
  (test-timvisher-agent-shell-send--with-shells nil
    (should (equal "no buffer" (timvisher-agent-shell-send-text "nope" "hello")))
    (should-not calls)))

(ert-deftest test-timvisher-agent-shell-send-reads-and-trims-the-file ()
  "The file's contents are sent with trailing whitespace trimmed."
  (let ((file (make-temp-file "tvass" nil nil "From the test agent\n\nhello\n\n")))
    (unwind-protect
        (test-timvisher-agent-shell-send--with-shells t
          (should (equal "queued" (timvisher-agent-shell-send "s1" file)))
          (should (equal '(("shell-s1" enqueue :prompt "From the test agent\n\nhello"))
                         calls)))
      (delete-file file))))

(ert-deftest test-timvisher-agent-shell-send-without-agent-shell ()
  "An Emacs that never loaded agent-shell reports no buffer."
  (cl-letf (((symbol-function 'agent-shell-buffers) nil))
    (should (equal "no buffer" (timvisher-agent-shell-send-text "s1" "hello")))))

(provide 'timvisher-agent-shell-send-test)
;;; timvisher-agent-shell-send-test.el ends here
