;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Packages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(package-initialize)

(add-to-list 'package-archives
             '("melpa-stable" . "https://stable.melpa.org/packages/")
             t)
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/")
             t)
(add-to-list 'package-archives
             '("marmalade" . "https://marmalade-repo.org/packages/")
             t)

(autoload 'package-pinned-packages "package")

(setq required-packages '(
                          (ag . "melpa-stable")
                          (bats-mode . "melpa")
                          (better-defaults . "melpa-stable")
                          (cider . "melpa-stable")
                          (clojure-mode . "melpa-stable")
                          (expand-region . "melpa-stable")
                          (ido-completing-read+ . "melpa-stable")
                          (ido-ubiquitous . "melpa-stable")
                          (ido-vertical-mode . "melpa-stable")
                          (magit . "melpa-stable")
                          (markdown-mode . "melpa-stable")
                          (paredit . "melpa-stable")
                          (php-mode . "melpa-stable")
                          (projectile . "melpa-stable")
                          (smex . "melpa-stable")
                          (yaml-mode . "melpa-stable")
                          ))

(defun install-required-packages ()
  (interactive)
  (mapc (lambda (package)
          (message "%s" (car package))
          (package-install (car package)))
        required-packages))

;;; Force us to be explicit about killing emacs
(global-unset-key (kbd "C-x C-c"))

;;; We never want to send mail from emacs
(global-unset-key (kbd "C-x m"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun header-comment (comment)
  "Insert a header COMMENT

A header comment is a line of comment characters fill-column
long, a line of 3 comment characters followed by a space then
COMMENT, and a line of comment characters fill-column long
again."
  (interactive "sComment: ")
  (let* ((comment-char (string-to-char comment-start))
         (wrapper (make-string fill-column comment-char))
         (comment-line (format "%s %s"
                               (make-string 3 comment-char)
                               comment)))
    (insert wrapper "\n" comment-line "\n" wrapper)))

(defun pbpaste ()
  (interactive)
  (shell-command "pbpaste" t))

(defun pbcopy-refilled-copy-refilled-from-temp-buffer ()
  (let ((text (buffer-substring-no-properties (region-beginning)
                                              (region-end))))
    (with-temp-buffer
      (insert text)
      (fill-paragraph)
      (let ((text (buffer-substring-no-properties (point-min)
                                                  (point-max))))
        (if (shell-command-on-region (point-min) (point-max) "pbcopy")
            (message "Sent to clipboard: %s" text)
          (error "Failed to send to clipobard: %s" text))))))

(defun pbcopy-refilled ()
  (interactive)
  (if (region-active-p)
      (pbcopy-refilled-copy-refilled-from-temp-buffer)
    (error "pbcopy-refilled must have an active region")))

(defun edit-init-file ()
  (interactive)
  (find-file (concat (getenv "HOME") "/.emacs.d/init.el")))

(defun paste-todo ()
  (interactive)
  (org-meta-return)
  (pbpaste))

(defun rjmetrics-read-box-project ()
  (let* ((directory "/core:/opt/code")
         (files (directory-files directory))
         (project (completing-read "Project: "
                                   files
                                   (lambda (file)
                                     (not
                                      (or (string= "." file)
                                          (string= ".." file))))
                                   t)))
    (format "%s/%s" directory project)))

(defun jump-to-project ()
  (interactive)
  (let* ((project (rjmetrics-read-box-project)))
    (if project
        (dired (format "%s/%s" directory project))
      (message "No project chosen"))))

(defvar rjmetrics-find-file-project nil)

(defun rjmetrics-find-file (arg)
  (interactive "p")
  (if (not rjmetrics-find-file-project)
      (setq rjmetrics-find-file-project (rjmetrics-read-box-project)))
  (let ((default-directory rjmetrics-find-file-project))
    (projectile-find-file arg)))

(defun rjmetrics-dired-code-dir
    ()
  (interactive)
  (dired "/core:/opt/code"))

(global-set-key (kbd "C-c C") 'rjmetrics-dired-code-dir)

(defun rjmetrics-clone-repo
    (github-username repository)
  (interactive "sGitHub username: \nsRepository name: ")
  (process-file "git"
                nil
                nil
                nil
                "clone"
                (format "git@github.com:RJMetrics/%s.git" repository))
  (magit-status repository)
  ;; TODO cache github-username for the duration of the session or allow
  ;; it be customizod on a per host basis
  (magit-remote-add github-username
                    (format "git@github.com:%s/%s.git"
                            github-username
                            repository)))

(autoload 'magit-toplevel "magit-git")
(autoload 'magit-process-file "magit-process")

(defun todo-frame-bounce
    ()
  (interactive)
  ;; create the todo frame if it doesn't exist
  (unless (boundp 'todo-frame-bounce-todo-frame)
    (setq todo-frame-bounce-todo-frame (make-frame)))
  (if (not (eq (tty-top-frame) todo-frame-bounce-todo-frame))
      ;; raise the proper frame
      (progn
        (setq todo-frame-bounce-prior-frame (tty-top-frame))
        (let ((todo-file (format "%s/%s"
                                 (or (magit-toplevel)
                                     (file-name-directory
                                      (buffer-file-name)))
                                 "todo.org")))
          (raise-frame todo-frame-bounce-todo-frame)
          (find-file todo-file)
          (delete-other-windows)))
    ;; go back to the other one
    (raise-frame todo-frame-bounce-prior-frame)))

(global-set-key (kbd "<f5>") 'todo-frame-bounce)

(defun github-parse-remote-url
    (remote-url)
  "Returns an alist of user and repo"
  (save-match-data
    (unless
        (string-match
         (concat "^\\(?:git@github.com:\\|https://github.com/\\)"
                 "\\([-A-Za-z0-9_]+\\)"
                 "/"
                 "\\([-A-Za-z0-9_]+\\)"
                 ".git")
         remote-url)
      (error (format "%s is not on github.com" (buffer-file-name))))
    (append (list (list 'user (match-string-no-properties 1 remote-url)))
            (list (list 'repo
                        (match-string-no-properties 2 remote-url))))))

(defun github-source-link
    ()
  (interactive)
  (let* ((remote-url (magit-get "remote" (magit-get-remote) "url"))
         (parsed (github-parse-remote-url remote-url))
         (user (car (alist-get 'user parsed)))
         (repo (car (alist-get 'repo parsed)))
         (commit-hash (magit-rev-parse "HEAD"))
         (starting-line (line-number-at-pos (if (region-active-p)
                                                (region-beginning)
                                              (point))))
         (ending-line (line-number-at-pos (if (region-active-p)
                                              (region-end)
                                            (point))))
         (link (format "https://github.com/%s/%s/blob/%s/%s#L%d"
                       user
                       repo
                       commit-hash
                       (magit-file-relative-name)
                       starting-line)))
    (message
     (if (/= starting-line ending-line)
         (format "%s-L%d" link ending-line)
       link))))

(defun github-parse-remote-and-branch
    (remote-and-branch-str)
  (save-match-data
    (string-match "\\(.+?\\)/\\(.+\\)" remote-and-branch-str)
    (list
     (list 'remote
           (match-string-no-properties 1 remote-and-branch-str))
     (list 'branch
           (match-string-no-properties 2 remote-and-branch-str)))))

(defun github-url-to-repo-name
    (github-url)
  (car (alist-get 'repo (github-parse-remote-url github-url))))

(defun github-url-to-user-name
    (github-url)
  (car (alist-get 'user (github-parse-remote-url github-url))))

(defun github-branch-to-remote-name
    (branch)
  (car (alist-get 'remote (github-parse-remote-and-branch branch))))

(defun github-branch-to-branch-name
    (branch)
  (car (alist-get 'branch (github-parse-remote-and-branch branch))))

(defun prefix-arg-count-p
    (arg count)
  (if (= 1 arg)
      (= 0 count)
    (if (= 0 (% arg 4))
        (= count (/ arg 4))
      (error "%d not evenly divisible by 4" arg))))

(defun github-compare
    (arg)
  (interactive "p")
  (let* ((base-remote (github-branch-to-remote-name
                       (magit-get-upstream-branch)))
         (base-branch (github-branch-to-branch-name
                       (magit-get-upstream-branch)))
         (base-remote-url (magit-get "remote" base-remote "url"))
         (project-name (github-url-to-repo-name base-remote-url))
         (base-user (github-url-to-user-name base-remote-url))
         (our-remote-url (magit-get "remote"
                                    (github-branch-to-remote-name
                                     (magit-get-push-branch))
                                    "url"))
         (our-user (github-url-to-user-name our-remote-url))
         (our-branch (github-branch-to-branch-name
                      (magit-get-push-branch)))
         (compare-link (format
                        (concat "https://github.com/"
                                ;; Base User like: RJMetrics
                                "%s/"
                                ;; Project name like: boxcutter
                                "%s/"
                                "compare/"
                                ;; Base Branch like: master
                                "%s..."
                                ;; our user like: timvisher
                                "%s:"
                                ;; our branch like: feature/support-sierra
                                "%s?expand=1")
                        base-user
                        project-name
                        base-branch
                        our-user
                        our-branch)))
    ;; like https://github.com/RJMetrics/boxcutter/compare/master...timvisher:feature/support-sierra?expand=1
    (message compare-link)
    (when (prefix-arg-count-p arg 1)
      (browse-url compare-link))))

(defun github-commit-link
    (arg)
  (interactive "p")
  (let* ((remote-name (github-branch-to-remote-name
                       (magit-get-push-branch)))
         (remote-url (magit-get "remote" remote-name "url"))
         (project-name (github-url-to-repo-name remote-url))
         (github-user (github-url-to-user-name remote-url))
         (commit-hash (magit-rev-parse
                       (magit-branch-or-commit-at-point)))
         (commit-link (format
                       (concat "https://github.com/"
                               ;; Push remote like: stitchdata
                               "%s/"
                               ;; Push project like: ide
                               "%s/"
                               "commit/"
                               ;; commit hash like: b9b11cc
                               "%s")
                       github-user
                       project-name
                       commit-hash)))
    (if (not commit-hash)
        (error "No commit at point!")
      ;; like: https://github.com/stitchdata/ide/commit/b9b11cc05baaf8383b2cc7968990a4fbf966c4a0
      (message commit-link)
      (when (prefix-arg-count-p arg 1)
        (browse-url commit-link)))))

(defun github-add-my-public (github-username)
  (interactive "sGitHub username: ")
  (let ((remote-url (magit-get "remote" (magit-get-remote "master") "url")))
    (save-match-data
      (string-match
       (concat
        ;; protocol
        "\\(?:https://\\|git@\\)"
        ;; host
        "github.com[:/]"
        ;; user
        "\\([-A-Za-z0-9_]+\\)"
        "/"
        ;; repo
        "\\([-A-Za-z0-9_]+\\)"
        ".git")
       remote-url)
      (let ((repo (match-string-no-properties 2 remote-url)))
        (magit-remote-add
         "public"
         ;; FIXME cache github-username or allow it to be configured per
         ;; host
         (format "git@github.com:%s/%s.git" github-username repo))))))

;;; Stefan Monnier <foo at acm.org>. It is the opposite of fill-paragraph
;;; https://www.emacswiki.org/emacs/UnfillParagraph
(defun unfill-paragraph (&optional region)
  "Takes a multi-line paragraph and makes it into a single line of text."
  (interactive (progn (barf-if-buffer-read-only) '(t)))
  (let ((fill-column (point-max))
        ;; This would override `fill-column' if it's an integer.
        (emacs-lisp-docstring-fill-column t))
    (fill-paragraph nil region)))

(global-set-key (kbd "M-Q") 'unfill-paragraph)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Keys
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(global-set-key (kbd "C-c i") 'edit-init-file)

(global-set-key (kbd "M-x") 'smex)

(global-set-key (kbd "C-c y") 'bury-buffer)

(global-set-key (kbd "C-c g") 'magit-status)

(global-set-key (kbd "C-h") 'backward-delete-char-untabify)

(global-set-key (kbd "C-c k") 'kill-whole-line)

(global-set-key (kbd "C-c r =") 'er/expand-region)
(autoload 'er/mark-inside-quotes "expand-region")
(global-set-key (kbd "C-c r i \"") 'er/mark-inside-quotes)
(global-set-key (kbd "C-c r i '") 'er/mark-inside-quotes)
(autoload 'er/mark-outside-quotes "expand-region")
(global-set-key (kbd "C-c r a \"") 'er/mark-outside-quotes)
(global-set-key (kbd "C-c r a '") 'er/mark-outside-quotes)
(autoload 'er/mark-inside-pairs "expand-region")
(global-set-key (kbd "C-c r i p") 'er/mark-inside-pairs)
(autoload 'er/mark-outside-pairs "expand-region")
(global-set-key (kbd "C-c r o p") 'er/mark-outside-pairs)

(global-set-key (kbd "C-c A") 'ag-project)

(global-set-key (kbd "C-c P") 'rjmetrics-find-file)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Aliases
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defalias 'yes-or-no-p 'y-or-n-p)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Hooks
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(add-hook 'emacs-lisp-mode-hook 'enable-paredit-mode)

(add-hook 'prog-mode-hook 'hs-minor-mode)

(add-hook 'prog-mode-hook 'fixme-mode)

(add-hook 'emacs-lisp-mode-hook 'eldoc-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; dired-x
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require 'dired-x)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; clojure-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun add-compojure-forms-to-clojure-dedenting ()
  (put-clojure-indent 'context 2)
  (put-clojure-indent 'ANY 2)
  (put-clojure-indent 'PUT 2)
  (put-clojure-indent 'GET 2)
  (put-clojure-indent 'POST 2)
  (put-clojure-indent 'DELETE 2)
  (put-clojure-indent 'PATCH 2))

(eval-after-load 'clojure-mode
  '(progn
     (add-hook 'clojure-mode-hook
               'add-compojure-forms-to-clojure-dedenting)
     (add-hook 'clojure-mode-hook 'enable-paredit-mode)
     (add-hook 'clojure-mode-hook 'eldoc-mode)
     (add-hook 'clojure-mode-hook 'whitespace-mode)))

(eval-after-load 'cider
  '(progn
     (add-hook 'cider-repl-mode-hook 'enable-paredit-mode)
     (add-hook 'cider-repl-mode-hook 'eldoc-mode)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; paredit
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun fix-paredit-keys ()
  (define-key
    paredit-mode-map
    (kbd "M-)")
    'paredit-forward-slurp-sexp))

(eval-after-load 'paredit
  '(fix-paredit-keys))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Customize
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(cider-repl-use-pretty-printing t)
 '(column-number-mode t)
 '(delete-selection-mode t)
 '(dired-dwim-target t)
 '(dired-recursive-copies (quote always))
 '(fill-column 74)
 '(frame-background-mode (quote light))
 '(global-hl-line-mode t)
 '(global-whitespace-mode nil)
 '(hippie-expand-try-functions-list
   (quote
    (try-complete-file-name-partially try-complete-file-name try-expand-all-abbrevs try-expand-dabbrev try-expand-dabbrev-all-buffers try-expand-dabbrev-from-kill try-complete-lisp-symbol-partially try-complete-lisp-symbol)))
 '(ido-ubiquitous-mode t)
 '(ido-vertical-mode t)
 '(js-indent-level 2)
 '(org-export-backends (quote (ascii html md)))
 '(org-refile-use-outline-path t)
 '(org-todo-keywords
   (quote
    ((sequence "TODO" "IN_PROGRESS" "|" "DONE" "CANCELLED")
     (sequence "DELEGATED" "|" "DONE" "CANCELLED"))))
 '(package-selected-packages
   (quote
    (align-cljlet
     org
     mediawiki
     coffee-mode
     yaml-mode
     smex
     projectile
     paredit
     markdown-mode
     magit
     ido-vertical-mode
     ido-ubiquitous
     fixme-mode
     expand-region
     cider
     better-defaults
     bats-mode
     ag
     terraform-mode
     coffee-mode
     php-mode)))
 '(projectile-global-mode t)
 '(projectile-mode-line " Projectile")
 '(safe-local-variable-values
   (quote
    ((sh-indent-for-case-alt . ++)
     (sh-indent-for-case-label . +))))
 '(search-default-mode (quote char-fold-to-regexp))
 '(sentence-end-double-space nil)
 '(whitespace-line-column nil)
 '(whitespace-style
   (quote
    (face
     trailing
     tabs
     newline
     empty
     space-after-tab
     space-before-tab
     tab-mark)))
 '(winner-mode t))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
