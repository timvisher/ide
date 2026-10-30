;;; timvisher-agent-shell-send.el --- Send a prompt to an agent-shell by session id -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Lets something outside Emacs (another agent, through emacsclient)
;; hand a prompt to one particular agent-shell:
;;
;;   emacsclient -s <socket> --eval \
;;     '(timvisher-agent-shell-send "<session-id>" "/abs/message-file")'
;;
;; The shell is picked by its session id rather than by project, so it
;; works when several shells share a project.  The prompt is queued when
;; the shell is busy or has unsent input at its prompt, and submitted
;; when it is idle with an empty prompt.

;;; Code:

(require 'map)
(require 'seq)
(require 'subr-x)

(declare-function agent-shell-buffers "agent-shell")
(declare-function agent-shell--state "agent-shell")
(declare-function agent-shell--prompt-queue-enqueue "agent-shell-prompt-queue")
(declare-function agent-shell--insert-to-shell-buffer "agent-shell")
(declare-function shell-maker-busy "shell-maker")

(defun timvisher-agent-shell-send-buffer (session-id)
  "Return the agent-shell buffer whose session id is SESSION-ID, or nil."
  (when (fboundp 'agent-shell-buffers)
    (seq-find (lambda (buffer)
                (with-current-buffer buffer
                  (equal session-id
                         (map-nested-elt (agent-shell--state) '(:session :id)))))
              (agent-shell-buffers))))

(defun timvisher-agent-shell--pending-input-p ()
  "Return non-nil when the current shell's prompt has unsent input."
  (when-let* ((process (get-buffer-process (current-buffer))))
    (not (string-blank-p
          (buffer-substring-no-properties (process-mark process) (point-max))))))

(defun timvisher-agent-shell-send-text (session-id text)
  "Queue or submit TEXT in the agent-shell whose session id is SESSION-ID.

Return \"queued\" when TEXT joined the shell's pending prompts, because
the shell was busy or someone has unsent input at its prompt,
\"submitted\" when it was idle with an empty prompt and TEXT was sent,
or \"no buffer\" when no live agent-shell has that session id.  A
queued prompt runs once the shell's current or next turn ends."
  (if-let* ((buffer (timvisher-agent-shell-send-buffer session-id)))
      (with-current-buffer buffer
        ;; Submitting would take the half-typed input at the prompt along
        ;; with TEXT, so it waits in the queue until that input is sent.
        (if (or (shell-maker-busy) (timvisher-agent-shell--pending-input-p))
            (progn
              (agent-shell--prompt-queue-enqueue :prompt text)
              "queued")
          (agent-shell--insert-to-shell-buffer
           :shell-buffer buffer :text text :submit t :no-focus t)
          "submitted"))
    "no buffer"))

(defun timvisher-agent-shell-send (session-id file)
  "Queue or submit FILE's contents in the agent-shell with SESSION-ID.

Trailing whitespace is trimmed.  Return what
`timvisher-agent-shell-send-text' returns."
  (timvisher-agent-shell-send-text
   session-id
   (with-temp-buffer
     (insert-file-contents file)
     (string-trim-right (buffer-string)))))

(provide 'timvisher-agent-shell-send)
;;; timvisher-agent-shell-send.el ends here
