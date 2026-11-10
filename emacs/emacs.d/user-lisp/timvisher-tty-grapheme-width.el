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
;;
;; `timvisher-tty-emoji-presentation-mode' additionally shows bare
;; symbols that only have color emoji glyphs, such as 🏳, as their
;; 2-column emoji on text terminals, by sending VS16 after them and
;; making them 2 columns in `char-width-table'.

;;; Code:

;; VS16 bases in Miscellaneous Symbols and Pictographs and Transport
;; and Map Symbols that `char-width' calls 1 column.  These exist only
;; as color emoji glyphs (Ghostty on macOS draws every one from Apple
;; Color Emoji), so Ghostty squeezes them into one cell or spills them
;; over the next.  Bases in other blocks, such as ⚠ ❤ ✔ ↔, have
;; monochrome text glyphs in ordinary fonts and are left as text.
(defconst timvisher-tty-grapheme-width--emoji-bases
  (concat "🌡🌤🌥🌦🌧🌨🌩🌪🌫🌬🌶🍽🎖🎗🎙🎚🎛🎞🎟🏋🏌🏍🏎🏔"
          "🏕🏖🏗🏘🏙🏚🏛🏜🏝🏞🏟🏳🏵🏷🐿👁📽🕉🕊🕯🕰🕳🕴🕵"
          "🕶🕷🕸🕹🖇🖊🖋🖌🖍🖐🖥🖨🖱🖲🖼🗂🗃🗄🗑🗒🗓🗜🗝🗞"
          "🗡🗣🗨🗯🗳🗺🛋🛍🛎🛏🛠🛡🛢🛣🛤🛥🛩🛰🛳")
  "Symbols `timvisher-tty-emoji-presentation-mode' shows as emoji.")

(defun timvisher-tty-grapheme-width--wide-cluster-p (chars)
  "Return non-nil if CHARS form a sequence the terminal draws 2 wide."
  (seq-some (lambda (c)
              (or (= c #xFE0F)
                  (= c #x200D)
                  (<= #x1F3FB c #x1F3FF)
                  (<= #xE0020 c #xE007F)))
            chars))

(defun timvisher-tty-grapheme-width--glyphs (gstring)
  "Return GSTRING's glyphs in order."
  (let (glyphs)
    (dotimes (i (lgstring-glyph-len gstring))
      (when-let* ((glyph (lgstring-glyph gstring i)))
        (push glyph glyphs)))
    (nreverse glyphs)))

(defun timvisher-tty-grapheme-width--one-cluster (glyphs width)
  "Make GLYPHS a single cluster WIDTH columns wide."
  (let ((last (1- (length glyphs))))
    (seq-do-indexed (lambda (glyph i)
                      (lglyph-set-from-to glyph 0 last)
                      (lglyph-set-width glyph (if (= i 0) width 0)))
                    glyphs)))

(defun timvisher-tty-grapheme-width--widen (gstring)
  "Make GSTRING one 2-column cluster if it is an emoji sequence.
Return GSTRING, modified in place."
  (let ((glyphs (timvisher-tty-grapheme-width--glyphs gstring)))
    ;; The whole gstring becomes a single cluster rather than widening
    ;; each of `compose-gstring-for-terminal''s clusters, because that
    ;; function splits a ZWJ sequence at the joiner while the terminal
    ;; draws the whole sequence in one cell.
    (when (timvisher-tty-grapheme-width--wide-cluster-p
           (mapcar #'lglyph-char glyphs))
      (timvisher-tty-grapheme-width--one-cluster glyphs 2))
    gstring))

(defun timvisher-tty-grapheme-width--narrow (gstring)
  "Make GSTRING one 1-column cluster.
Return GSTRING, modified in place."
  (timvisher-tty-grapheme-width--one-cluster
   (timvisher-tty-grapheme-width--glyphs gstring) 1)
  gstring)

(defun timvisher-tty-grapheme-width--present (gstring direction)
  "Compose GSTRING for an emoji base on a graphic display.
DIRECTION is as for `compose-gstring-for-graphic'."
  (compose-gstring-for-graphic gstring direction))

(defun timvisher-tty-grapheme-width--add-vs16 (gstring)
  "Append VS16 to GSTRING's single base glyph and make it 2 columns.
Return the resulting gstring."
  (let* ((base (lgstring-glyph gstring 0))
         (vs16 (lglyph-copy base)))
    (lglyph-set-char vs16 #xFE0F)
    (lglyph-set-width vs16 0)
    (lglyph-set-width base 2)
    (lgstring-insert-glyph gstring 1 vs16)))

(defun timvisher-tty-grapheme-width-compose
    (func from to font-object string direction)
  "Compose like `auto-compose-chars', widening emoji on text terminals.
FUNC, FROM, TO, FONT-OBJECT, STRING and DIRECTION are as for
`auto-compose-chars'."
  (let ((gstring (auto-compose-chars func from to font-object string
                                     direction)))
    (cond
     ((or (null gstring) (fontp font-object 'font-object)) gstring)
     ((and (eq func #'timvisher-tty-grapheme-width--present)
           (= 1 (- to from)))
      (timvisher-tty-grapheme-width--add-vs16 gstring))
     ;; The presentation mode makes these bases 2 columns in
     ;; `char-width-table', which would otherwise size an explicit
     ;; text-presentation sequence 2 wide; terminals draw it 1 wide.
     ((and (eq func #'timvisher-tty-grapheme-width--present)
           (memq #xFE0E (mapcar #'lglyph-char
                                (timvisher-tty-grapheme-width--glyphs
                                 gstring))))
      (timvisher-tty-grapheme-width--narrow gstring))
     (t (timvisher-tty-grapheme-width--widen gstring)))))

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

(defun timvisher-tty-grapheme-width--presentation-rule (char)
  "Return the composition rule that presents CHAR as emoji."
  ;; The rule absorbs a following VS15 or VS16 itself because once it
  ;; claims CHAR the display engine never tries the selector's own
  ;; look-back rule, which it shadows; `--present' does that rule's job
  ;; on graphic frames.
  (vector (concat (string char) "[\uFE0E\uFE0F]?")
          0
          #'timvisher-tty-grapheme-width--present))

(defvar timvisher-tty-emoji-presentation--saved-widths nil
  "Alist of (CHAR . WIDTH) `char-width-table' entries the mode replaced.")

;;;###autoload
(define-minor-mode timvisher-tty-emoji-presentation-mode
  "Show bare color-only emoji symbols as 2-column emoji on text terminals.
Symbols in `timvisher-tty-grapheme-width--emoji-bases' are sent to the
terminal followed by VS16, as though written with it, unless the text
already follows them with VS15 or VS16.  The mode also makes them 2
columns wide in `char-width-table', so `string-width' and
`current-column' count them as displayed.  Use together with
`timvisher-tty-grapheme-width-mode'."
  :global t
  :group 'display
  (seq-doseq (char timvisher-tty-grapheme-width--emoji-bases)
    (let* ((rule (timvisher-tty-grapheme-width--presentation-rule char))
           (rules (remove rule (aref composition-function-table char))))
      (set-char-table-range composition-function-table char
                            (if timvisher-tty-emoji-presentation-mode
                                (append rules (list rule))
                              rules))))
  ;; Emacs 32 gives a wide terminal composition its second, padding
  ;; glyph only when `char-width-table' calls its first character wide.
  ;; Widening the composition alone leaves one glyph for two columns,
  ;; and redisplay loses track of the screen after it.
  (if timvisher-tty-emoji-presentation-mode
      (unless timvisher-tty-emoji-presentation--saved-widths
        (seq-doseq (char timvisher-tty-grapheme-width--emoji-bases)
          (push (cons char (aref char-width-table char))
                timvisher-tty-emoji-presentation--saved-widths)
          (set-char-table-range char-width-table char 2)))
    (pcase-dolist (`(,char . ,width)
                   timvisher-tty-emoji-presentation--saved-widths)
      (set-char-table-range char-width-table char width))
    (setq timvisher-tty-emoji-presentation--saved-widths nil))
  (clear-composition-cache))

(provide 'timvisher-tty-grapheme-width)
;;; timvisher-tty-grapheme-width.el ends here
