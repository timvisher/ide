;;; timvisher-tty-grapheme-width.el --- Terminal widths for emoji grapheme clusters -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; On text terminals Emacs sizes a composed grapheme cluster as the
;; sum of its codepoints' `char-width-table' widths.  Terminals that
;; implement Unicode grapheme clustering (Ghostty's mode 2027, tmux
;; with `variation-selector-always-wide') draw an emoji sequence
;; containing VS16, ZWJ, a skin-tone modifier or emoji tags as one
;; 2-column cell, so Emacs's cursor model drifts from the screen and
;; redisplay garbles the line.
;;
;; `timvisher-tty-grapheme-width-mode' makes text-terminal compositions
;; of those sequences 2 columns wide.  Graphic frames are untouched.

;;; Code:

(defun timvisher-tty-grapheme-width--wide-cluster-p (chars)
  "Return non-nil if CHARS form a sequence the terminal draws 2 wide."
  (seq-some (lambda (c)
              (or (= c #xFE0F)
                  (= c #x200D)
                  (<= #x1F3FB c #x1F3FF)
                  (<= #xE0020 c #xE007F)))
            chars))

(defun timvisher-tty-grapheme-width--widen (gstring)
  "Make GSTRING one 2-column cluster if it is an emoji sequence.
Return GSTRING, modified in place."
  (let (glyphs)
    (dotimes (i (lgstring-glyph-len gstring))
      (when-let* ((glyph (lgstring-glyph gstring i)))
        (push glyph glyphs)))
    (setq glyphs (nreverse glyphs))
    ;; The whole gstring becomes a single cluster rather than widening
    ;; each of `compose-gstring-for-terminal''s clusters, because that
    ;; function splits a ZWJ sequence at the joiner while the terminal
    ;; draws the whole sequence in one cell.
    (when (timvisher-tty-grapheme-width--wide-cluster-p
           (mapcar #'lglyph-char glyphs))
      (let ((last (1- (length glyphs))))
        (seq-do-indexed (lambda (glyph i)
                          (lglyph-set-from-to glyph 0 last)
                          (lglyph-set-width glyph (if (= i 0) 2 0)))
                        glyphs)))
    gstring))

(defun timvisher-tty-grapheme-width-compose
    (func from to font-object string direction)
  "Compose like `auto-compose-chars', widening emoji on text terminals.
FUNC, FROM, TO, FONT-OBJECT, STRING and DIRECTION are as for
`auto-compose-chars'."
  (let ((gstring (auto-compose-chars func from to font-object string
                                     direction)))
    (if (and gstring (not (fontp font-object 'font-object)))
        (timvisher-tty-grapheme-width--widen gstring)
      gstring)))

;;;###autoload
(define-minor-mode timvisher-tty-grapheme-width-mode
  "Size emoji grapheme clusters on text terminals as 2 columns.
Use this with terminals that cluster graphemes, such as Ghostty and
tmux 3.6 or later, so that Emacs's idea of the cursor column matches
the screen."
  :global t
  :group 'display
  (setq-default auto-composition-function
                (if timvisher-tty-grapheme-width-mode
                    #'timvisher-tty-grapheme-width-compose
                  #'auto-compose-chars))
  (clear-composition-cache))

(provide 'timvisher-tty-grapheme-width)
;;; timvisher-tty-grapheme-width.el ends here
