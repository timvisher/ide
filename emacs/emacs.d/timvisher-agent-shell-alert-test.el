;;; timvisher-agent-shell-alert-test.el --- Tests for timvisher-agent-shell-alert -*- lexical-binding: t; -*-

;;; Commentary:
;; Terminal detection, OSC payload selection, tmux DCS passthrough and
;; notification dispatch.  Moved here from the agent-shell-plus fork when
;; notification delivery moved into user config.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'timvisher-agent-shell-alert)

(ert-deftest timvisher-agent-shell-alert--detect-terminal-term-program-test ()
  "Test terminal detection via TERM_PROGRAM."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("TERM_PROGRAM" "iTerm.app")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "iTerm.app"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-ghostty-env-test ()
  "Test terminal detection via GHOSTTY_RESOURCES_DIR fallback."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("GHOSTTY_RESOURCES_DIR" "/usr/share/ghostty")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "ghostty"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-kitty-env-test ()
  "Test terminal detection via KITTY_PID fallback."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("KITTY_PID" "12345")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "kitty"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-conemu-env-test ()
  "Test terminal detection via ConEmuPID fallback."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("ConEmuPID" "9876")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "ConEmu"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-vte-env-test ()
  "Test terminal detection via VTE_VERSION fallback."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("VTE_VERSION" "7200")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "vte"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-urxvt-term-test ()
  "Test terminal detection via TERM=rxvt fallback."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("TERM" "rxvt-unicode-256color")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "urxvt"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-foot-term-test ()
  "Test terminal detection via TERM=foot fallback."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("TERM" "foot")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "foot"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-mintty-term-test ()
  "Test terminal detection via TERM=mintty fallback."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("TERM" "mintty")
                 (_ nil)))))
    (should (equal (timvisher-agent-shell-alert--detect-terminal) "mintty"))))

(ert-deftest timvisher-agent-shell-alert--detect-terminal-unknown-test ()
  "Test terminal detection returns nil for unknown terminals."
  (cl-letf (((symbol-function 'getenv)
             (lambda (_var &optional _frame) nil)))
    (should-not (timvisher-agent-shell-alert--detect-terminal))))

(ert-deftest timvisher-agent-shell-alert--osc-payload-kitty-test ()
  "Test OSC 99 payload generation for kitty."
  (cl-letf (((symbol-function 'timvisher-agent-shell-alert--detect-terminal)
             (lambda () "kitty")))
    (should (equal (timvisher-agent-shell-alert--osc-payload "Title" "Body")
                   "\e]99;i=1:d=0;Title\e\\\e]99;i=1:p=body;Body\e\\"))))

(ert-deftest timvisher-agent-shell-alert--osc-payload-osc777-test ()
  "Test OSC 777 payload generation for urxvt and VTE terminals."
  (cl-letf (((symbol-function 'timvisher-agent-shell-alert--detect-terminal)
             (lambda () "urxvt")))
    (should (equal (timvisher-agent-shell-alert--osc-payload "Title" "Body")
                   "\e]777;notify;Title;Body\e\\"))))

(ert-deftest timvisher-agent-shell-alert--osc-payload-osc9-test ()
  "Test OSC 9 payload generation for iTerm2/Ghostty/WezTerm/foot/mintty/ConEmu."
  (cl-letf (((symbol-function 'timvisher-agent-shell-alert--detect-terminal)
             (lambda () "iTerm.app")))
    (should (equal (timvisher-agent-shell-alert--osc-payload "Title" "Body")
                   "\e]9;Body\e\\"))))

(ert-deftest timvisher-agent-shell-alert--osc-payload-unsupported-terminal-test ()
  "Test that unsupported terminals return nil."
  (cl-letf (((symbol-function 'timvisher-agent-shell-alert--detect-terminal)
             (lambda () "Apple_Terminal")))
    (should-not (timvisher-agent-shell-alert--osc-payload "Title" "Body"))))

(ert-deftest timvisher-agent-shell-alert--tmux-passthrough-bare-terminal-test ()
  "Test no wrapping outside tmux."
  (cl-letf (((symbol-function 'getenv)
             (lambda (_var &optional _frame) nil)))
    (should (equal (timvisher-agent-shell-alert--tmux-passthrough "payload")
                   "payload"))))

(ert-deftest timvisher-agent-shell-alert--tmux-passthrough-disabled-test ()
  "Test nil return when tmux passthrough is disabled."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("TMUX" "/tmp/tmux-501/default,12345,0")
                 (_ nil))))
            ((symbol-function 'timvisher-agent-shell-alert--tmux-allow-passthrough-p)
             (lambda () nil)))
    (should-not (timvisher-agent-shell-alert--tmux-passthrough "\e]9;hi\e\\"))))

(ert-deftest timvisher-agent-shell-alert--tmux-passthrough-enabled-test ()
  "Test DCS wrapping when tmux passthrough is enabled."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var &optional _frame)
               (pcase var
                 ("TMUX" "/tmp/tmux-501/default,12345,0")
                 (_ nil))))
            ((symbol-function 'timvisher-agent-shell-alert--tmux-allow-passthrough-p)
             (lambda () t)))
    (should (equal (timvisher-agent-shell-alert--tmux-passthrough "\e]9;hi\e\\")
                   "\ePtmux;\e\e]9;hi\e\e\\\e\\"))))

(ert-deftest timvisher-agent-shell-alert-notify-dispatches-to-mac-when-available-test ()
  "Test that notify dispatches to ns-do-applescript on GUI macOS."
  (let ((notified nil)
        (system-type 'darwin))
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&rest _) t))
              ((symbol-function 'ns-do-applescript)
               (lambda (script)
                 (setq notified script))))
      (timvisher-agent-shell-alert-notify "Test" "Hello")
      (should (stringp notified))
      (should (string-match-p "display notification" notified)))))

(ert-deftest timvisher-agent-shell-alert-notify-falls-back-to-osascript-no-terminal-test ()
  "Test osascript fallback when no terminal is detected on macOS."
  (let ((osascript-called nil))
    (cl-letf (((symbol-function 'timvisher-agent-shell-alert--mac-available-p)
               (lambda () nil))
              ((symbol-function 'display-graphic-p)
               (lambda (&rest _) nil))
              ((symbol-function 'timvisher-agent-shell-alert--detect-terminal)
               (lambda () nil))
              ((symbol-function 'timvisher-agent-shell-alert--osascript-notify)
               (lambda (title body)
                 (setq osascript-called (list title body)))))
      (let ((system-type 'darwin))
        (timvisher-agent-shell-alert-notify "T" "B")
        (should (equal osascript-called '("T" "B")))))))

(ert-deftest timvisher-agent-shell-alert-notify-falls-back-to-osascript-unsupported-test ()
  "Test osascript fallback when terminal is detected but not OSC-capable."
  (let ((osascript-called nil))
    (cl-letf (((symbol-function 'timvisher-agent-shell-alert--mac-available-p)
               (lambda () nil))
              ((symbol-function 'display-graphic-p)
               (lambda (&rest _) nil))
              ((symbol-function 'timvisher-agent-shell-alert--detect-terminal)
               (lambda () "Apple_Terminal"))
              ((symbol-function 'timvisher-agent-shell-alert--osascript-notify)
               (lambda (title body)
                 (setq osascript-called (list title body)))))
      (let ((system-type 'darwin))
        (timvisher-agent-shell-alert-notify "T" "B")
        (should (equal osascript-called '("T" "B")))))))

(ert-deftest timvisher-agent-shell-alert-notify-sends-osc-in-known-terminal-test ()
  "Test that notify sends OSC in a known terminal."
  (let ((sent nil))
    (cl-letf (((symbol-function 'timvisher-agent-shell-alert--mac-available-p)
               (lambda () nil))
              ((symbol-function 'display-graphic-p)
               (lambda (&rest _) nil))
              ((symbol-function 'timvisher-agent-shell-alert--detect-terminal)
               (lambda () "iTerm.app"))
              ((symbol-function 'timvisher-agent-shell-alert--tmux-passthrough)
               (lambda (seq) seq))
              ((symbol-function 'send-string-to-terminal)
               (lambda (str) (setq sent str))))
      (timvisher-agent-shell-alert-notify "T" "B")
      (should (equal sent "\e]9;B\e\\")))))

(provide 'timvisher-agent-shell-alert-test)

;;; timvisher-agent-shell-alert-test.el ends here
