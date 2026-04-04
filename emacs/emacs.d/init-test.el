;;; init-test.el --- Tests for init.el functions -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for source-link and Claude source link functions defined in init.el
;;
;; These tests verify the Claude source link generation functionality, which
;; creates references in the format "@/path/to/file:line" or "@/path/to/file:start-end".
;;
;; Test Isolation:
;; The function being tested modifies global state (the kill ring), so tests must
;; save and restore kill ring state to ensure proper isolation between test runs.

;;; Code:

(require 'ert)

;;; Tests for source-link--get-line-range

(ert-deftest test-source-link--get-line-range-single-line ()
  "Test getting line range for a single line (no region).

Verifies that when point is on a line without an active region, the function
returns a range where start-line and end-line are the same."
  (with-temp-buffer
    (insert "line 1\nline 2\nline 3\n")
    (goto-char (point-min))
    (forward-line 1)  ; Move to line 2
    (let ((range (source-link--get-line-range)))
      (should (= 2 (plist-get range :start-line)))
      (should (= 2 (plist-get range :end-line))))))

(ert-deftest test-source-link--get-line-range-multi-line ()
  "Test getting line range for a multi-line region.

Verifies that when a region spans multiple lines, the function returns the
correct start and end line numbers for the entire region."
  (with-temp-buffer
    (insert "line 1\nline 2\nline 3\nline 4\n")
    (goto-char (point-min))
    (forward-line 1)  ; Start at line 2
    (set-mark (point))
    (forward-line 2)  ; End at line 4
    (activate-mark)
    (let ((range (source-link--get-line-range)))
      (should (= 2 (plist-get range :start-line)))
      (should (= 4 (plist-get range :end-line))))))

(ert-deftest test-source-link--get-line-range-first-line ()
  "Test getting line range for the first line.

Verifies edge case: when point is on the first line (line 1), the function
correctly returns 1 for both start and end line numbers."
  (with-temp-buffer
    (insert "line 1\nline 2\nline 3\n")
    (goto-char (point-min))
    (let ((range (source-link--get-line-range)))
      (should (= 1 (plist-get range :start-line)))
      (should (= 1 (plist-get range :end-line))))))

(ert-deftest test-source-link--get-line-range-region-within-line ()
  "Test getting line range for a region within a single line.

Verifies that when a region is active but entirely within a single line, the
function returns the same line number for both start and end (treating it as
a single-line range)."
  (with-temp-buffer
    (insert "line 1\nthis is a long line with content\nline 3\n")
    (goto-char (point-min))
    (forward-line 1)
    (forward-char 5)  ; Position in middle of line 2
    (set-mark (point))
    (forward-char 10) ; Select some chars on same line
    (activate-mark)
    (let ((range (source-link--get-line-range)))
      (should (= 2 (plist-get range :start-line)))
      (should (= 2 (plist-get range :end-line))))))

;;; Tests for timvisher-EXP-claude-source-link

(ert-deftest test-claude-source-link-single-line ()
  "Test Claude source link for a single line.

Verifies that when point is on a single line (no active region), the generated
link has the format @/path/to/file:LINE without a range."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))  ; Save kill ring state for isolation
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (forward-line 1)  ; Move to line 2
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-match-p (regexp-quote test-file) link))
              (should (string-match-p ":2$" link))
              (should-not (string-match-p ":[0-9]+-[0-9]+$" link)))))
      (setq kill-ring saved-kill-ring)  ; Restore kill ring
      (delete-file test-file))))

(ert-deftest test-claude-source-link-multi-line ()
  "Test Claude source link for a multi-line region.

Verifies that when a region spans multiple lines, the generated link has the
format @/path/to/file:START-END with both line numbers."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))  ; Save kill ring state for isolation
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\nline 4\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (forward-line 1)  ; Start at line 2
            (set-mark (point))
            (forward-line 2)  ; End at line 4
            (activate-mark)
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-match-p (regexp-quote test-file) link))
              (should (string-match-p ":2-4$" link)))))
      (setq kill-ring saved-kill-ring)  ; Restore kill ring
      (delete-file test-file))))

(ert-deftest test-claude-source-link-format ()
  "Test that Claude source link uses the @ prefix format.

Verifies that the generated link starts with @ and matches the expected pattern.
Note: On line 1 without region, no line number is included (references whole file)."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))  ; Save kill ring state for isolation
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (forward-line 1)  ; Move to line 2 to avoid line-1 special case
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-prefix-p "@" link))
              (should (string-match-p "^@.+:[0-9]+$" link)))))
      (setq kill-ring saved-kill-ring)  ; Restore kill ring
      (delete-file test-file))))

(ert-deftest test-claude-source-link-no-file ()
  "Test that Claude source link errors when buffer has no file.

Verifies that the function signals an error when called in a buffer that is not
visiting a file, since there's no file path to include in the link."
  (with-temp-buffer
    (insert "some content\n")
    (should-error (timvisher-EXP-claude-source-link)
                  :type 'error)))

(ert-deftest test-claude-source-link-line-1-no-region ()
  "Test Claude source link on line 1 without region references whole file.

When point is on line 1 with no active region, the link should be @/path/to/file
without any line number, referencing the entire file."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))  ; On line 1
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string= link (format "@%s" test-file)))
              (should-not (string-match-p ":[0-9]" link)))))
      (setq kill-ring saved-kill-ring)
      (delete-file test-file))))

(ert-deftest test-claude-source-link-line-1-with-region ()
  "Test Claude source link on line 1 with region references line 1 only.

When point is on line 1 with an active region, the link should respect the
explicit selection and include :1 to reference specifically line 1."
  (let ((test-file (make-temp-file "test_claude_link" nil ".el"))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (with-temp-file test-file
            (insert "line 1\nline 2\nline 3\n"))
          (with-current-buffer (find-file-noselect test-file)
            (goto-char (point-min))
            (set-mark (point))
            (end-of-line)
            (activate-mark)
            (timvisher-EXP-claude-source-link)
            (let ((link (car kill-ring)))
              (should (string-match-p (regexp-quote test-file) link))
              (should (string-match-p ":1$" link)))))
      (setq kill-ring saved-kill-ring)
      (delete-file test-file))))

(ert-deftest test-claude-source-link-dired-single-file ()
  "Test Claude source link in dired for file at point.

In dired with no marks and no region, should @ the file at point."
  (let ((test-dir (make-temp-file "test_dired" t))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (let ((test-file-1 (expand-file-name "file1.txt" test-dir))
                (test-file-2 (expand-file-name "file2.txt" test-dir)))
            (write-region "content1\n" nil test-file-1)
            (write-region "content2\n" nil test-file-2)
            (let ((dired-buf (dired test-dir)))
              (with-current-buffer dired-buf
                ;; Ensure we're in the dired buffer
                (should (eq major-mode 'dired-mode))
                ;; Find first actual file (not . or ..)
                (goto-char (point-min))
                (while (and (not (eobp))
                            (let ((file (dired-get-filename nil t)))
                              (or (null file)
                                  (member (file-name-nondirectory file) '("." "..")))))
                  (dired-next-line 1))
                (timvisher-EXP-claude-source-link)
                (let ((link (car kill-ring)))
                  (should (string-prefix-p "@" link))
                  (should (or (string-match-p "file1\\.txt" link)
                              (string-match-p "file2\\.txt" link))))))))
      (setq kill-ring saved-kill-ring)
      (delete-directory test-dir t))))

(ert-deftest test-claude-source-link-dired-marked-files ()
  "Test Claude source link in dired for marked files.

In dired with marked files, should @ all marked files as newline-separated list."
  (let ((test-dir (make-temp-file "test_dired" t))
        (saved-kill-ring kill-ring))
    (unwind-protect
        (let ((interprogram-paste-function nil)
              (interprogram-cut-function nil))
          (let ((test-file-1 (expand-file-name "file1.txt" test-dir))
                (test-file-2 (expand-file-name "file2.txt" test-dir)))
            (write-region "content1\n" nil test-file-1)
            (write-region "content2\n" nil test-file-2)
            (let ((dired-buf (dired test-dir)))
              (with-current-buffer dired-buf
                ;; Ensure we're in the dired buffer
                (should (eq major-mode 'dired-mode))
                ;; Find and mark both actual files (not . or ..)
                (goto-char (point-min))
                (let ((files-marked 0))
                  (while (and (not (eobp)) (< files-marked 2))
                    (let ((file (dired-get-filename nil t)))
                      (when (and file
                                 (not (member (file-name-nondirectory file) '("." ".."))))
                        (dired-mark 1)  ; Mark and move to next line
                        (setq files-marked (1+ files-marked)))
                      (unless (and file
                                   (not (member (file-name-nondirectory file) '("." ".."))))
                        (dired-next-line 1)))))
                (timvisher-EXP-claude-source-link)
                (let ((link (car kill-ring)))
                  (should (string-match-p "file1\\.txt" link))
                  (should (string-match-p "file2\\.txt" link))
                  (should (string-match-p "\n" link)))))))
      (setq kill-ring saved-kill-ring)
      (delete-directory test-dir t))))

(provide 'init-test)
;;; init-test.el ends here
