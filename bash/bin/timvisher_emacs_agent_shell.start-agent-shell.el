(setq frame-background-mode 'light)

(setq load-prefer-newer t)

(require 'agent-shell)

(setq agent-shell-session-strategy 'new)

(setq agent-shell-anthropic-authentication
      (agent-shell-anthropic-make-authentication
       :api-key (getenv "ANTHROPIC_API_KEY")))

(setq agent-shell-openai-authentication
      (agent-shell-openai-make-authentication :api-key (getenv "OPENAI_API_KEY")))

(setq timvisher--codex-prompt
      (or (getenv "timvisher_codex_prompt")
          "Do a deep repo investigation. Use tools extensively: list files, run ripgrep, open and inspect files, and run any lightweight tests or repro scripts you find. Summarize findings and propose next steps.

_**DO NOT UNDER ANY CIRCUMSTANCES EDIT ANYTHING. YOUR GOAL IS PURE INVESTIGATION AND REPORTING.**_"))

(setq timvisher--shell-buffer
      (funcall (intern (getenv "timvisher_agent_start_fn"))))

(agent-shell-insert
 :text timvisher--codex-prompt
 :submit t
 :shell-buffer timvisher--shell-buffer)

(if (not noninteractive)
    (delete-other-windows)
  ;; Batch mode: wait for the turn to complete, print buffer, exit.
  (let ((timvisher--batch-done nil)
        (timvisher--heartbeat-timer nil)
        (timvisher--start-time (float-time)))
    ;; Heartbeat: print status every 30 seconds.
    (setq timvisher--heartbeat-timer
          (run-with-timer
           30 30
           (lambda ()
             (let ((elapsed (- (float-time) timvisher--start-time)))
               (message "[agent-shell batch] %.0fs elapsed, waiting for turn to complete..."
                        elapsed)))))
    ;; Subscribe to turn-complete.
    (with-current-buffer timvisher--shell-buffer
      (agent-shell-subscribe-to
       :shell-buffer timvisher--shell-buffer
       :event 'turn-complete
       :on-event (lambda (&rest _)
                   (setq timvisher--batch-done t))))
    ;; Spin the event loop until the turn finishes.
    (while (not timvisher--batch-done)
      (accept-process-output nil 1))
    (when timvisher--heartbeat-timer
      (cancel-timer timvisher--heartbeat-timer))
    ;; Dump the buffer contents to stdout.
    (with-current-buffer timvisher--shell-buffer
      (princ (buffer-substring-no-properties (point-min) (point-max))))
    (kill-emacs 0)))
