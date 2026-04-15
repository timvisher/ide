;;; bd-org.el --- Incremental beads-to-org sync -*- lexical-binding: t -*-

;; Apply a manifest of rendered bead/memory text to an org file,
;; updating only the entries that changed.

;;; Code:

(require 'org)
(require 'json)

;; -- Finding entries by property ------------------------------------------

(defun bd-org--find-property-heading (property value)
  "Find heading whose PROPERTY drawer entry matches VALUE.
Move point to heading start and return point, or nil if not found."
  (goto-char (point-min))
  (let ((found nil)
        (prop-re (concat ":" property ": +"
                         (regexp-quote value)
                         "\\s-*$")))
    (while (and (not found)
                (re-search-forward prop-re nil t))
      (save-excursion
        (org-back-to-heading t)
        (setq found (point))))
    (when found
      (goto-char found)
      found)))

;; -- Subtree operations ---------------------------------------------------

(defun bd-org--subtree-text ()
  "Return text of current subtree from heading start to subtree end."
  (save-excursion
    (org-back-to-heading t)
    (let ((beg (point)))
      (org-end-of-subtree t t)
      ;; Trim trailing blank lines to normalize for comparison
      (skip-chars-backward " \t\n")
      (forward-line 1)
      (buffer-substring-no-properties beg (point)))))

(defun bd-org--replace-subtree (new-text)
  "Replace current subtree with NEW-TEXT."
  (org-back-to-heading t)
  (let ((beg (point)))
    (org-end-of-subtree t t)
    ;; Include trailing blank line if present
    (when (looking-at "^\\s-*$")
      (forward-line 1))
    (delete-region beg (point))
    (insert new-text)
    (unless (bolp) (insert "\n"))))

;; -- Section management ---------------------------------------------------

(defun bd-org--find-section (section-name)
  "Find top-level (* ) heading matching SECTION-NAME.
Returns point at heading start, or nil."
  (save-excursion
    (goto-char (point-min))
    (let ((re (concat "^\\* "
                      (regexp-quote section-name)
                      "\\(\\s-\\|$\\)")))
      (when (re-search-forward re nil t)
        (org-back-to-heading t)
        (point)))))

(defun bd-org--ensure-section (section-name section-order all-sections)
  "Ensure a top-level section heading for SECTION-NAME exists.
ALL-SECTIONS is an alist of (name . order).  A new section is
inserted respecting order.  Returns point at heading start."
  (or (bd-org--find-section section-name)
      ;; Create the section in the right position.
      (let ((insert-before nil))
        ;; Find the first existing section whose order is higher.
        (dolist (sec all-sections)
          (when (and (not insert-before)
                     (< section-order (cdr sec)))
            (let ((pos (bd-org--find-section (car sec))))
              (when pos
                (setq insert-before pos)))))
        (if insert-before
            (progn
              (goto-char insert-before)
              (insert "* " section-name "\n\n")
              (forward-line -2)
              (beginning-of-line)
              (point))
          ;; Append at end
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (unless (looking-back "\n\n" (- (point) 2))
            (insert "\n"))
          (insert "* " section-name "\n")
          (forward-line -1)
          (beginning-of-line)
          (point)))))

(defun bd-org--section-insert-point (section-name section-order all-sections)
  "Return buffer position where a new entry should be appended in SECTION-NAME."
  (let ((sec-pos (bd-org--ensure-section
                  section-name section-order all-sections)))
    (goto-char sec-pos)
    (org-end-of-subtree t t)
    ;; Back up over trailing blank lines so insertion stays inside the
    ;; section.
    (skip-chars-backward " \t\n")
    (end-of-line)
    (point)))

;; -- Upsert (update-or-insert) -------------------------------------------

(defun bd-org--upsert-entry (prop-name prop-value
                             section-name section-order
                             all-sections rendered-text)
  "Update or insert an entry identified by PROP-NAME=PROP-VALUE.
If found in the buffer, replace only if the rendered text differs.
If not found, append to SECTION-NAME."
  (if (bd-org--find-property-heading prop-name prop-value)
      ;; Found — compare and replace if needed
      (let ((current (bd-org--subtree-text))
            (clean-new (string-trim-right rendered-text)))
        (unless (string= (string-trim-right current) clean-new)
          (bd-org--replace-subtree (concat clean-new "\n"))))
    ;; Not found — insert at end of section
    (let ((pos (bd-org--section-insert-point
                section-name section-order all-sections)))
      (goto-char pos)
      (insert "\n\n" (string-trim-right rendered-text) "\n"))))

;; -- File header management -----------------------------------------------

(defun bd-org--update-generated-timestamp ()
  "Update the #+GENERATED: line to current time."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+GENERATED:.*$" nil t)
      (replace-match
       (format "#+GENERATED: %s"
               (format-time-string "[%Y-%m-%d %a %H:%M]"
                                   (current-time) t))))))

(defun bd-org--ensure-file-header (header-text)
  "Ensure the file starts with HEADER-TEXT if the file is new/empty."
  (when (= (point-min) (point-max))
    (insert header-text "\n")))

;; -- Main sync entry point ------------------------------------------------

(defun bd-org-sync (org-file manifest-file)
  "Apply MANIFEST-FILE to ORG-FILE incrementally.
Only entries that differ from the current file content are touched."
  (let* ((json-object-type 'alist)
         (json-array-type 'vector)
         (json-key-type 'symbol)
         (manifest (json-read-file manifest-file))
         (file-header (alist-get 'file_header manifest))
         (sections-vec (alist-get 'sections manifest))
         (beads-vec (alist-get 'beads manifest))
         (memories-vec (alist-get 'memories manifest))
         (all-sections (mapcar (lambda (s)
                                 (cons (alist-get 'name s)
                                       (alist-get 'order s)))
                               (append sections-vec nil))))
    ;; Open the file
    (find-file org-file)
    (bd-org--ensure-file-header file-header)
    ;; Process beads
    (dolist (bead (append beads-vec nil))
      (let ((bead-id (alist-get 'bead_id bead))
            (section (alist-get 'section bead))
            (order (alist-get 'section_order bead))
            (rendered (alist-get 'rendered bead)))
        (bd-org--upsert-entry "BEAD_ID" bead-id
                              section order all-sections
                              rendered)))
    ;; Process memories
    (dolist (mem (append memories-vec nil))
      (let ((key (alist-get 'memory_key mem))
            (rendered (alist-get 'rendered mem)))
        (bd-org--upsert-entry "MEMORY_KEY" key
                              "Memories" 6 all-sections
                              rendered)))
    ;; Update generated timestamp
    (bd-org--update-generated-timestamp)
    (save-buffer)
    (message "bd-org-sync: updated %s (%d beads, %d memories)"
             org-file
             (length beads-vec)
             (length memories-vec))))

;; -- Batch entry point ----------------------------------------------------

(defun bd-org-sync-batch ()
  "Entry point for emacs --batch.
Usage: emacs --batch -l bd-org.el -f bd-org-sync-batch ORG-FILE MANIFEST-FILE"
  (let ((org-file (pop command-line-args-left))
        (manifest-file (pop command-line-args-left)))
    (unless (and org-file manifest-file)
      (error "Usage: emacs --batch -l bd-org.el -f bd-org-sync-batch ORG-FILE MANIFEST-FILE"))
    (bd-org-sync org-file manifest-file)))

(provide 'bd-org)
;;; bd-org.el ends here
