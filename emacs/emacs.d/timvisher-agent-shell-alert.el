;;; timvisher-agent-shell-alert.el --- Desktop notifications for agent-shell -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Notify when an agent-shell prompt is idle and waiting for input.
;;
;; agent-shell emits an `idle' event (armed after `turn-complete' and
;; `permission-request', cancelled by agent activity, delayed by
;; `agent-shell-idle-timeout') and leaves delivery to the consumer.  This
;; is that consumer.
;;
;; Originally agent-shell-alert.el in the agent-shell-plus fork.  Moved
;; here because upstream provides the hook and expects notification
;; delivery to live in user config.
;;
;; GUI Emacs on macOS:
;;
;;   Uses `ns-do-applescript' to run AppleScript's `display
;;   notification' from within the Emacs process.  Because the
;;   notification originates from Emacs itself, macOS attributes it to
;;   Emacs: the Emacs icon appears and clicking the notification
;;   activates Emacs.  No compilation, no dynamic module, no external
;;   dependencies.
;;
;;   A JIT-compiled Objective-C dynamic module using
;;   UNUserNotificationCenter (inspired by vterm-module.so) worked on an
;;   adhoc-signed Emacs built from source, but failed with UNErrorDomain
;;   error 1 (UNErrorCodeNotificationsNotAllowed) on the Homebrew
;;   emacs-app cask build from emacsformacosx.com.  Apple's docs say no
;;   entitlement is needed for local notifications and the hardened
;;   runtime has no notification-related restrictions, so the root cause
;;   is unclear.  `ns-do-applescript' gives essentially native
;;   notifications for free and works on every macOS Emacs build.
;;
;; Terminal Emacs:
;;
;;   Auto-detects the host terminal emulator and sends the appropriate
;;   OSC escape sequence: OSC 9 (iTerm2, Ghostty, WezTerm, foot,
;;   mintty, ConEmu), OSC 99 (kitty), or OSC 777 (urxvt, VTE-based
;;   terminals), with DCS passthrough for tmux (when
;;   allow-passthrough is enabled).
;;
;; Fallback:
;;
;;   Falls back to osascript on macOS when the terminal is unknown or
;;   tmux passthrough is not available.  On non-macOS platforms where
;;   the terminal is unrecognized, no OS-level notification is sent.
;;
;; Terminal detection and DCS wrapping are inspired by clipetty's
;; approach.

;;; Code:

(require 'map)
(require 'subr-x)

(declare-function shell-maker-busy "shell-maker")
(declare-function agent-shell-subscribe-to "agent-shell")

(defvar timvisher-agent-shell-alert--osascript-warned nil
  "Non-nil after the osascript fallback warning has been shown.")

(defun timvisher-agent-shell-alert--detect-terminal ()
  "Detect the host terminal emulator.

Inside tmux, TERM_PROGRAM is \"tmux\", so we query tmux's global
environment for the outer terminal.  Falls back to terminal-specific
environment variables that survive tmux session inheritance.

  ;; In iTerm2:
  (timvisher-agent-shell-alert--detect-terminal)
  ;; => \"iTerm.app\"

  ;; In kitty inside tmux:
  (timvisher-agent-shell-alert--detect-terminal)
  ;; => \"kitty\""
  (let ((tp (getenv "TERM_PROGRAM" (selected-frame))))
    (cond
     ((and tp (not (string= tp "tmux")))
      tp)
     ((string= tp "tmux")
      (when-let ((raw (ignore-errors
                        (string-trim
                         (shell-command-to-string
                          "tmux show-environment -g TERM_PROGRAM 2>/dev/null")))))
        (when (string-match "^TERM_PROGRAM=\\(.+\\)" raw)
          (let ((val (match-string 1 raw)))
            (unless (string= val "tmux")
              val)))))
     ((getenv "GHOSTTY_RESOURCES_DIR" (selected-frame))
      "ghostty")
     ((getenv "ITERM_SESSION_ID" (selected-frame))
      "iTerm.app")
     ((getenv "WEZTERM_EXECUTABLE" (selected-frame))
      "WezTerm")
     ((getenv "KITTY_PID" (selected-frame))
      "kitty")
     ((getenv "ConEmuPID" (selected-frame))
      "ConEmu")
     ((getenv "VTE_VERSION" (selected-frame))
      "vte")
     ((when-let ((term (getenv "TERM" (selected-frame))))
        (string-match-p "^rxvt" term))
      "urxvt")
     ((when-let ((term (getenv "TERM" (selected-frame))))
        (string-match-p "^foot" term))
      "foot")
     ((when-let ((term (getenv "TERM" (selected-frame))))
        (string-match-p "^mintty" term))
      "mintty"))))

(defun timvisher-agent-shell-alert--osc-payload (title body)
  "Build the raw OSC notification payload for TITLE and BODY.

Selects the OSC protocol based on the detected terminal:
OSC 9 for iTerm2, Ghostty, WezTerm, foot, mintty, ConEmu;
OSC 99 for kitty; OSC 777 for urxvt and VTE-based terminals.
Returns nil if the terminal does not support OSC notifications.

  (timvisher-agent-shell-alert--osc-payload \"Done\" \"Task finished\")
  ;; => \"\\e]9;Task finished\\e\\\\\"  (in iTerm2)

  (timvisher-agent-shell-alert--osc-payload \"Done\" \"Task finished\")
  ;; => nil  (in Apple Terminal)"
  (let ((terminal (timvisher-agent-shell-alert--detect-terminal)))
    (pcase terminal
      ("kitty"
       (format "\e]99;i=1:d=0;%s\e\\\e]99;i=1:p=body;%s\e\\" title body))
      ;; Extend these lists as users report supported terminals.
      ((or "urxvt" "vte")
       (format "\e]777;notify;%s;%s\e\\" title body))
      ((or "iTerm.app" "ghostty" "WezTerm" "foot" "mintty" "ConEmu")
       (format "\e]9;%s\e\\" body)))))

(defun timvisher-agent-shell-alert--tmux-allow-passthrough-p ()
  "Return non-nil if tmux has allow-passthrough enabled.

  ;; With `set -g allow-passthrough on':
  (timvisher-agent-shell-alert--tmux-allow-passthrough-p)
  ;; => t"
  (when-let ((out (ignore-errors
                    (string-trim
                     (shell-command-to-string
                      "tmux show-option -gv allow-passthrough 2>/dev/null")))))
    (string= out "on")))

(defun timvisher-agent-shell-alert--tmux-passthrough (seq)
  "Wrap SEQ in tmux DCS passthrough if inside tmux.

Returns SEQ unchanged outside tmux.  Returns nil if inside tmux
but allow-passthrough is not enabled, signaling the caller to
fall back to osascript.

  ;; Inside tmux with passthrough enabled:
  (timvisher-agent-shell-alert--tmux-passthrough \"\\e]9;hi\\e\\\\\")
  ;; => \"\\ePtmux;\\e\\e]9;hi\\e\\\\\\e\\\\\"

  ;; Outside tmux:
  (timvisher-agent-shell-alert--tmux-passthrough \"\\e]9;hi\\e\\\\\")
  ;; => \"\\e]9;hi\\e\\\\\""
  (if (not (getenv "TMUX" (selected-frame)))
      seq
    (when (timvisher-agent-shell-alert--tmux-allow-passthrough-p)
      (let ((escaped (replace-regexp-in-string "\e" "\e\e" seq t t)))
        (concat "\ePtmux;" escaped "\e\\")))))

(defun timvisher-agent-shell-alert--osascript-notify (title body)
  "Send a macOS notification via osascript as a fallback.

TITLE and BODY are the notification title and message.

  (timvisher-agent-shell-alert--osascript-notify \"agent-shell\" \"Done\")"
  (unless timvisher-agent-shell-alert--osascript-warned
    (setq timvisher-agent-shell-alert--osascript-warned t)
    (message "timvisher-agent-shell-alert: using osascript for notifications.\
 For native terminal notifications:")
    (message "  - Use a terminal that supports OSC 9 \
(iTerm2, Ghostty, WezTerm) or OSC 99 (Kitty)")
    (when (getenv "TMUX" (selected-frame))
      (message "  - Enable tmux passthrough: \
set -g allow-passthrough on")))
  (call-process "osascript" nil 0 nil
                "-e"
                (format "display notification %S with title %S"
                        body title)))

(defun timvisher-agent-shell-alert-notify (title body)
  "Send a desktop notification with TITLE and BODY.

In GUI Emacs on macOS, uses `ns-do-applescript' to run `display
notification' from within the Emacs process so the notification
is attributed to Emacs (Emacs icon, click activates Emacs).  In
terminal Emacs, auto-detects the terminal emulator and sends the
appropriate OSC escape sequence, with tmux DCS passthrough when
available.  Falls back to osascript on macOS when the terminal is
unknown or tmux passthrough is not enabled.

  (timvisher-agent-shell-alert-notify \"agent-shell\" \"Turn complete\")"
  (cond
   ;; GUI Emacs on macOS: use ns-do-applescript for Emacs-branded
   ;; notifications (Emacs icon, click activates Emacs).
   ((and (eq system-type 'darwin)
         (display-graphic-p)
         (fboundp 'ns-do-applescript))
    (condition-case nil
        (ns-do-applescript
         (format "display notification %S with title %S" body title))
      (error
       (timvisher-agent-shell-alert--osascript-notify title body))))
   ;; Terminal: try OSC escape sequences for terminal notifications.
   ((not (display-graphic-p))
    (if-let ((payload (timvisher-agent-shell-alert--osc-payload title body))
             (wrapped (timvisher-agent-shell-alert--tmux-passthrough payload)))
        (send-string-to-terminal wrapped)
      (when (eq system-type 'darwin)
        (timvisher-agent-shell-alert--osascript-notify title body))))
   ;; GUI on macOS without ns-do-applescript (shouldn't happen), or
   ;; non-macOS GUI: fall back to osascript or just message.
   ((eq system-type 'darwin)
    (timvisher-agent-shell-alert--osascript-notify title body))))

(defun timvisher-agent-shell-alert--on-idle (event)
  "Notify that the shell behind EVENT is waiting for input.
Does nothing while the shell is busy."
  (when-let* ((buffer (map-nested-elt event '(:data :buffer)))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (unless (shell-maker-busy)
        (unless (eq buffer (window-buffer (selected-window)))
          (message "agent-shell: Prompt is waiting for input"))
        (timvisher-agent-shell-alert-notify
         "agent-shell" "Prompt is waiting for input")))))

(defun timvisher-agent-shell-alert-subscribe ()
  "Subscribe the current agent-shell buffer to idle notifications.
Intended for `agent-shell-mode-hook'.  No-ops on agent-shell versions
predating the `idle' event."
  (when (fboundp 'agent-shell-subscribe-to)
    (agent-shell-subscribe-to
     :shell-buffer (current-buffer)
     :event 'idle
     :on-event #'timvisher-agent-shell-alert--on-idle)))

(provide 'timvisher-agent-shell-alert)

;;; timvisher-agent-shell-alert.el ends here
