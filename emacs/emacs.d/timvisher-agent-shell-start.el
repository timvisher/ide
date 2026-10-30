;;; timvisher-agent-shell-start.el --- Start an agent-shell with a prompt -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Lets something outside Emacs (another agent, ntmux3, through
;; emacsclient) start a new agent-shell in this Emacs and hand it a
;; first prompt:
;;
;;   emacsclient -s <socket> --eval \
;;     '(timvisher-agent-shell-start "claude" "/abs/prompt-file")'
;;
;; The shell works in this Emacs's `agent-shell-cwd-function' directory,
;; the worktree for an ntmux3 Emacs.  Poll
;; `timvisher-agent-shell-start-status' with the returned buffer name for
;; the new session id.  Both return JSON strings for `timvisher_emacs
;; session start'.

;;; Code:

(require 'map)
(require 'subr-x)

(declare-function agent-shell--state "agent-shell")
(declare-function agent-shell--start "agent-shell")
(declare-function agent-shell--insert-to-shell-buffer "agent-shell")
(declare-function agent-shell-anthropic-make-claude-code-config "agent-shell-anthropic")
(declare-function agent-shell-openai-make-codex-config "agent-shell-openai")

(defun timvisher-agent-shell-start-status (buffer-name)
  "Return the agent-shell BUFFER-NAME's status as JSON.

The record has buffer, live and session_id, which is null until the
agent has opened its session."
  (let ((buffer (get-buffer buffer-name)))
    (json-serialize
     `((buffer . ,buffer-name)
       (live . ,(if (buffer-live-p buffer) t :false))
       (session_id . ,(or (and (buffer-live-p buffer)
                               (with-current-buffer buffer
                                 (map-nested-elt (agent-shell--state) '(:session :id))))
                          :null))))))

(defun timvisher-agent-shell-start (agent &optional prompt-file)
  "Start a new AGENT agent-shell, submitting PROMPT-FILE's contents when ready.

AGENT is \"claude\" or \"codex\".  The shell starts without taking
focus, and the prompt, trailing whitespace trimmed, is submitted once
the shell is ready.  Return `timvisher-agent-shell-start-status' for
the new shell."
  (unless (fboundp 'agent-shell--start)
    (require 'agent-shell))
  (let* ((config (pcase agent
                   ("claude" (agent-shell-anthropic-make-claude-code-config))
                   ("codex" (agent-shell-openai-make-codex-config))
                   (_ (error "Unknown agent %S; expected claude or codex" agent))))
         (prompt (when prompt-file
                   (with-temp-buffer
                     (insert-file-contents prompt-file)
                     (string-trim-right (buffer-string)))))
         ;; agent-shell--start rather than the agent's start command: the
         ;; commands display and focus the new shell, which would pull it
         ;; into the frame Tim is working in.
         (buffer (agent-shell--start :config config
                                     :session-strategy 'new
                                     :new-session t
                                     :no-focus t)))
    (when prompt
      (agent-shell--insert-to-shell-buffer
       :shell-buffer buffer :text prompt :submit t :no-focus t))
    (timvisher-agent-shell-start-status (buffer-name buffer))))

(provide 'timvisher-agent-shell-start)
;;; timvisher-agent-shell-start.el ends here
