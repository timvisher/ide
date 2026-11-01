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

(defun timvisher-tty-grapheme-width-test--compose (string)
  "Compose all of STRING for the selected text-terminal frame."
  (clear-composition-cache)
  (timvisher-tty-grapheme-width-compose
   #'font-shape-gstring 0 (length string) (selected-frame) string nil))

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

(provide 'timvisher-tty-grapheme-width-test)
;;; timvisher-tty-grapheme-width-test.el ends here
