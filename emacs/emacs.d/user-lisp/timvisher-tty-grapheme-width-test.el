;;; timvisher-tty-grapheme-width-test.el --- Tests for timvisher-tty-grapheme-width -*- lexical-binding: t; -*-

;;; Commentary:
;; Text-terminal composition widths for emoji sequences, and the mode
;; toggle.  Batch Emacs runs on a text-terminal frame, so compositions
;; here take the same `compose-gstring-for-terminal' path as `emacs -nw'.
;; Tests that enable the mode restore `auto-composition-function'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'timvisher-tty-grapheme-width)

(defun timvisher-tty-grapheme-width-test--compose (string &optional func)
  "Compose all of STRING for the selected text-terminal frame.
FUNC is the composition rule's function, `font-shape-gstring' if nil."
  (clear-composition-cache)
  (timvisher-tty-grapheme-width-compose
   (or func #'font-shape-gstring) 0 (length string) (selected-frame) string
   nil))

(defun timvisher-tty-grapheme-width-test--chars (gstring)
  "Return the characters of GSTRING's glyphs."
  (let (chars)
    (dotimes (i (lgstring-glyph-len gstring))
      (when-let* ((glyph (lgstring-glyph gstring i)))
        (push (lglyph-char glyph) chars)))
    (nreverse chars)))

(defun timvisher-tty-grapheme-width-test--width (gstring)
  "Return the total column width of GSTRING's glyphs."
  (let ((width 0))
    (dotimes (i (lgstring-glyph-len gstring))
      (when-let* ((glyph (lgstring-glyph gstring i)))
        (setq width (+ width (lglyph-width glyph)))))
    width))

(defun timvisher-tty-grapheme-width-test--clusters (gstring)
  "Return the distinct (FROM . TO) clusters of GSTRING's glyphs."
  (let (clusters)
    (dotimes (i (lgstring-glyph-len gstring))
      (when-let* ((glyph (lgstring-glyph gstring i)))
        (cl-pushnew (cons (lglyph-from glyph) (lglyph-to glyph)) clusters
                    :test #'equal)))
    (nreverse clusters)))

(ert-deftest timvisher-tty-grapheme-width-vs16-test ()
  "A text-default base followed by VS16 is one 2-column cluster."
  (let ((gstring (timvisher-tty-grapheme-width-test--compose "⚠️")))
    (should (= 2 (timvisher-tty-grapheme-width-test--width gstring)))
    (should (equal '((0 . 1))
                   (timvisher-tty-grapheme-width-test--clusters gstring)))))

(ert-deftest timvisher-tty-grapheme-width-zwj-test ()
  "A ZWJ sequence is one 2-column cluster, not one per joined emoji."
  (dolist (string '("\U0001F3F3️‍\U0001F308"
                    "\U0001F468‍\U0001F469‍\U0001F467"))
    (let ((gstring (timvisher-tty-grapheme-width-test--compose string)))
      (should (= 2 (timvisher-tty-grapheme-width-test--width gstring)))
      (should (= 1 (length (timvisher-tty-grapheme-width-test--clusters
                            gstring)))))))

(ert-deftest timvisher-tty-grapheme-width-modifier-and-tag-test ()
  "Skin-tone modifiers, keycaps and tag flags are 2 columns."
  (dolist (string '("\U0001F44D\U0001F3FD"
                    "1️⃣"
                    "\U0001F3F4\U000E0067\U000E0062\U000E0073\U000E0063\U000E0074\U000E007F"))
    (should (= 2 (timvisher-tty-grapheme-width-test--width
                  (timvisher-tty-grapheme-width-test--compose string))))))

(ert-deftest timvisher-tty-grapheme-width-plain-combining-test ()
  "Compositions without emoji selectors keep their usual width."
  (should (= 1 (timvisher-tty-grapheme-width-test--width
                (timvisher-tty-grapheme-width-test--compose "é")))))

(ert-deftest timvisher-tty-grapheme-width-mode-toggle-test ()
  "The mode installs its composer and restores `auto-compose-chars'."
  (let ((saved (default-value 'auto-composition-function))
        (saved-mode timvisher-tty-grapheme-width-mode))
    (unwind-protect
        (progn
          (timvisher-tty-grapheme-width-mode 1)
          (should (eq #'timvisher-tty-grapheme-width-compose
                      (default-value 'auto-composition-function)))
          (timvisher-tty-grapheme-width-mode -1)
          (should (eq #'auto-compose-chars
                      (default-value 'auto-composition-function))))
      (timvisher-tty-grapheme-width-mode (if saved-mode 1 -1))
      (setq-default auto-composition-function saved))))

(ert-deftest timvisher-tty-grapheme-width-presentation-bare-test ()
  "A bare emoji base is sent with VS16 and is 2 columns."
  (let ((gstring (timvisher-tty-grapheme-width-test--compose
                  "\U0001F3F3" #'timvisher-tty-grapheme-width--present)))
    (should (equal '(#x1F3F3 #xFE0F)
                   (timvisher-tty-grapheme-width-test--chars gstring)))
    (should (= 2 (timvisher-tty-grapheme-width-test--width gstring)))))

(ert-deftest timvisher-tty-grapheme-width-presentation-selector-test ()
  "An explicit VS16 is not doubled and an explicit VS15 stays text."
  (let ((vs16 (timvisher-tty-grapheme-width-test--compose
               "\u26A0\uFE0F" #'timvisher-tty-grapheme-width--present)))
    (should (equal '(#x26A0 #xFE0F)
                   (timvisher-tty-grapheme-width-test--chars vs16)))
    (should (= 2 (timvisher-tty-grapheme-width-test--width vs16))))
  (let ((vs15 (timvisher-tty-grapheme-width-test--compose
               "\u26A0\uFE0E" #'timvisher-tty-grapheme-width--present)))
    (should (equal '(#x26A0 #xFE0E)
                   (timvisher-tty-grapheme-width-test--chars vs15)))
    (should (= 1 (timvisher-tty-grapheme-width-test--width vs15)))))

(ert-deftest timvisher-tty-grapheme-width-presentation-mode-toggle-test ()
  "The mode appends its rule after existing ones and removes it again."
  (let ((saved-mode timvisher-tty-emoji-presentation-mode)
        (rule (timvisher-tty-grapheme-width--presentation-rule #x1F3F3))
        flag-rules)
    (unwind-protect
        (progn
          (timvisher-tty-emoji-presentation-mode -1)
          (setq flag-rules (aref composition-function-table #x1F3F3))
          (timvisher-tty-emoji-presentation-mode 1)
          (timvisher-tty-emoji-presentation-mode 1)
          (should (equal (append flag-rules (list rule))
                         (aref composition-function-table #x1F3F3)))
          (should (member (timvisher-tty-grapheme-width--presentation-rule
                           #x1F575)
                          (aref composition-function-table #x1F575)))
          (should-not (member (timvisher-tty-grapheme-width--presentation-rule
                               #x26A0)
                              (aref composition-function-table #x26A0)))
          (should-not (aref composition-function-table ?\s))
          (timvisher-tty-emoji-presentation-mode -1)
          (should (equal flag-rules
                         (aref composition-function-table #x1F3F3))))
      (timvisher-tty-emoji-presentation-mode (if saved-mode 1 -1)))))

(ert-deftest timvisher-tty-grapheme-width-presentation-char-width-test ()
  "The mode makes its bases 2 columns wide and restores them when off.
Emacs 32 pads a wide terminal composition only when its first
character is wide in `char-width-table'."
  (let ((saved-mode timvisher-tty-emoji-presentation-mode))
    (unwind-protect
        (progn
          (timvisher-tty-emoji-presentation-mode -1)
          (should (= 1 (char-width #x1F329)))
          (timvisher-tty-emoji-presentation-mode 1)
          (timvisher-tty-emoji-presentation-mode 1)
          (should (= 2 (char-width #x1F329)))
          (should (= 1 (char-width #x26A0)))
          (timvisher-tty-emoji-presentation-mode -1)
          (should (= 1 (char-width #x1F329))))
      (timvisher-tty-emoji-presentation-mode (if saved-mode 1 -1)))))

(ert-deftest timvisher-tty-grapheme-width-presentation-text-selector-test ()
  "A base the mode widens stays 1 column when the text asks for VS15."
  (let ((saved-mode timvisher-tty-emoji-presentation-mode))
    (unwind-protect
        (progn
          (timvisher-tty-emoji-presentation-mode 1)
          (let ((gstring (timvisher-tty-grapheme-width-test--compose
                          "\U0001F3F3︎"
                          #'timvisher-tty-grapheme-width--present)))
            (should (equal '(#x1F3F3 #xFE0E)
                           (timvisher-tty-grapheme-width-test--chars gstring)))
            (should (= 1 (timvisher-tty-grapheme-width-test--width gstring)))))
      (timvisher-tty-emoji-presentation-mode (if saved-mode 1 -1)))))

(provide 'timvisher-tty-grapheme-width-test)
;;; timvisher-tty-grapheme-width-test.el ends here
