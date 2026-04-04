(setq startup-time (current-time))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Packages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Attempts to allow elpa.gnu.org to be contacted from macOS
;;; https://emacs.stackexchange.com/questions/68288/error-retrieving-https-elpa-gnu-org-packages-archive-contents
(when (and (equal emacs-version "27.2")
           (eql system-type 'darwin))
  (setq gnutls-algorithm-priority "NORMAL:-VERS-TLS1.3"))

(when (< emacs-major-version 27)
  (display-warning :warning "Please upgrade your emacs version to at least 27.1")
  (package-initialize))

(add-to-list 'package-archives
             '("melpa-stable" . "https://stable.melpa.org/packages/")
             t)
;; (add-to-list 'package-archives
;;              '("melpa" . "https://melpa.org/packages/")
;;              t)
;; (add-to-list 'package-archives
;;              '("marmalade" . "https://marmalade-repo.org/packages/")
;;              t)
;; (add-to-list 'package-archives
;;              '("org" . "https://orgmode.org/elpa/")
;;              t)

(autoload 'package-pinned-packages "package")

(load "eglot")

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

(defun pbcopy-unfilled-copy-from-temp-buffer
    ()
  (let ((text (buffer-substring-no-properties (region-beginning)
                                              (region-end))))
    (with-temp-buffer
      (insert text)
      (mark-whole-buffer)
      (unfill-paragraph t)
      (let ((text (buffer-substring-no-properties (point-min)
                                                  (point-max))))
        (if (shell-command-on-region (point-min) (point-max) "pbcopy")
            (message "Sent to clipboard: %s" text)
          (error "Failed to send to clipobard: %s" text))))))

(defun pbcopy-unfilled
    ()
  (interactive)
  (when (not (region-active-p))
    (error "pbcopy-unfilled must have an active region"))
  (pbcopy-unfilled-copy-from-temp-buffer))

(defun edit-init-file ()
  (interactive)
  (find-file (concat user-emacs-directory "init.el")))

(defun ide--xdg-extension-directory-name
    ()
  (format "%s/timvisher/ide/emacs"
          (or (getenv "XDG_CONFIG_HOME")
              "~/.config")))

(defun ide--system-extension-theme-directory-name
    ()
  (concat (ide--xdg-extension-directory-name)
          "/"
          system-name
          "/themes"))

(defun ide--system-extension-file-name ()
  (concat (ide--xdg-extension-directory-name)
          "/"
          system-name
          ".el"))

(defun ide-edit-system-extension-file ()
  (interactive)
  (find-file (ide--system-extension-file-name)))

(defun prefix-arg
    (count)
  (expt 4 count))

(autoload 'magit-toplevel "magit-git")
(autoload 'magit-get "magit-git")
(autoload 'magit-process-file "magit-process")

(defun ide-frame-bounce-todo
    ()
  (interactive)
  ;; create the todo frame if it doesn't exist
  (unless (boundp '-ide-frame-bounce-todo-frame)
    (setq -ide-frame-bounce-todo-frame (make-frame)))
  (unless (boundp '-ide-frame-bounce-special-frames)
    (setq -ide-frame-bounce-special-frames '()))
  (add-to-list '-ide-frame-bounce-special-frames
               -ide-frame-bounce-todo-frame)
  (if (not (eq (tty-top-frame) -ide-frame-bounce-todo-frame))
      ;; raise the proper frame
      (progn
        (unless (memq (tty-top-frame) -ide-frame-bounce-special-frames)
          (setq -ide-frame-bounce-prior-frame (tty-top-frame)))
        (raise-frame -ide-frame-bounce-todo-frame)
        (let ((todo-file (format "%s/%s"
                                 (or (magit-toplevel)
                                     (file-name-directory
                                      (buffer-file-name)))
                                 "todo.org")))
          (find-file todo-file))
        (delete-other-windows))
    ;; go back to the other one
    (raise-frame -ide-frame-bounce-prior-frame)))
(define-obsolete-function-alias 'todo-frame-bounce 'ide-frame-bounce-todo "2019-11-11 09:05")

(global-set-key (kbd "<f5>") 'ide-frame-bounce-todo)

(defun github-parse-remote-url
    (remote-url)
  "Returns an alist of user and repo"
  (when (stringp remote-url)
    (save-match-data
      (unless
          (string-match
           (concat "^"
                   ;; All the prefixes we know about
                   "\\(?:git@github.com:"
                   "\\|https://github.com/"
                   "\\|git://github.com/\\)"

                   "\\([-A-Za-z0-9_]+\\)"
                   "/"
                   "\\([-A-Za-z0-9_.]+\\)"
                   "\\(?:.git\\)?")
           remote-url)
        (error (format "%s is not on github.com" (buffer-file-name))))
      (append (list (list 'user (match-string-no-properties 1 remote-url)))
              (list (list 'repo
                          (match-string-no-properties 2 remote-url)))))))

(defun source-link--get-line-range ()
  "Get the line range for the current point or region.
Returns a plist with :start-line and :end-line."
  (let ((start-line (line-number-at-pos (if (use-region-p)
                                           (region-beginning)
                                         (point))))
        (end-line (line-number-at-pos (if (use-region-p)
                                         (region-end)
                                       (point)))))
    (list :start-line start-line :end-line end-line)))

(defun github-browse-file-url
    ()
  (interactive)
  (let* ((file-path (magit-file-relative-name))
         (remote-url (magit-get "remote" (magit-get-remote) "url"))
         (parsed (github-parse-remote-url remote-url))
         (user (car (alist-get 'user parsed)))
         (repo (car (alist-get 'repo parsed)))
         (commit-hash (magit-rev-parse "HEAD"))
         ;; https://github.com/<user>/<repo>/blob/<commit shash>/<file path>
         (file-url (format "https://github.com/%s/%s/blob/%s/%s"
                           user
                           repo
                           commit-hash
                           file-path)))
    (message
     "%s"
     (url-encode-url file-url))))

(defun github-source-link-string
    (arg)
  (when (magit-anything-modified-p nil (or (buffer-file-name) "."))
    (error (concat "Cannot generate a source link as there "
                   "are modifications in the source tree.")))
  (let* ((remote-url (or (magit-get "remote" (magit-get-push-remote) "url")
                         (magit-get "remote" (magit-get-remote) "url")))
         (user (github-url-to-user-name remote-url))
         (repo (github-url-to-repo-name remote-url))
         (commit-hash (if (prefix-arg-count-p arg 1)
                          (magit-get-current-branch)
                        (or magit-buffer-revision
                            (magit-rev-parse "HEAD"))))
         (line-range (source-link--get-line-range))
         (starting-line (plist-get line-range :start-line))
         (ending-line (plist-get line-range :end-line))
         (link (if (or (string-suffix-p ".md" (magit-file-relative-name))
                       (= 1 starting-line ending-line)
                       dired-directory)
                   (format "https://github.com/%s/%s/blob/%s/%s"
                           user
                           repo
                           commit-hash
                           (magit-file-relative-name))
                 (format "https://github.com/%s/%s/blob/%s/%s#L%d%s"
                         user
                         repo
                         commit-hash
                         (magit-file-relative-name)
                         starting-line
                         (if (/= starting-line ending-line)
                             (format "-L%d" ending-line)
                           ""))))
         (encoded-link (url-encode-url
                        link)))
    encoded-link))

(defun github-source-link
    (arg)
  "Displays a link to the currently highlighted source code in github.

The link defaults to the current commit's link for stability.

With a single prefix arg, the link will use the current branch
rather than the current commit's hash."
  (interactive "p")
  ;; TODO an idea here would be to not just error out but somehow verify
  ;; that nothing has changed since the last public commit for _this file_
  ;; at least and then generate a link based on that. In that way it's the
  ;; _remote's_ commit that matters (as we know that has at least been
  ;; published) and whether or not there's a diff from there.
  (let* ((encoded-link (github-source-link-string arg)))
    (kill-new encoded-link)
    (message "Saved %s to the kill ring"
             encoded-link)))

(defun github-parse-remote-and-branch
    (remote-and-branch-str)
  (when (stringp remote-and-branch-str)
    (save-match-data
      (string-match "\\(.+?\\)/\\(.+\\)" remote-and-branch-str)
      (list
       (list 'remote
             (match-string-no-properties 1 remote-and-branch-str))
       (list 'branch
             (match-string-no-properties 2 remote-and-branch-str))))))

(defun github-url-to-repo-name
    (github-url)
  (when (stringp github-url)
    (string-replace
     ".git"
     ""
     (car (alist-get 'repo (github-parse-remote-url github-url))))))

(defun github-url-to-user-name
    (github-url)
  (car (alist-get 'user (github-parse-remote-url github-url))))

(defun github-branch-to-remote-name
    (branch)
  (car (alist-get 'remote (github-parse-remote-and-branch branch))))

(defun github-branch-to-branch-name
    (branch)
  (car (alist-get 'branch (github-parse-remote-and-branch branch))))

(defun ide--prefix-arg-count
    (prefix-arg)
  (let ((c (log prefix-arg 4)))
    (if (not (= (truncate c) c))
        (error "%d not a power of 4" prefix-arg)
      (truncate c))))

(defun ide--prefix-
    (prefix-arg count)
  "Subtract COUNT prefixes from prefix-arg

Errors if prefix-arg is not a power of 4 or if there aren't
enough prefix args to subtract."
  (let ((arg-count (ide--prefix-arg-count prefix-arg)))
    (when (< arg-count count)
      (error "Not enough prefix args (%d) to subtract %d"
             arg-count
             count))
    (expt 4 (- arg-count count))))

(defun ide--prefix-arg-count-p
    (prefix-arg count)
  "Predicate returns true if raw PREFIX-ARG matches COUNT"
  (and prefix-arg
       (= count (ide--prefix-arg-count prefix-arg))))

(defalias 'prefix-arg-count-p 'ide--prefix-arg-count-p)
(make-obsolete 'prefix-arg-count-p 'ide--prefix-arg-count-p "2019-04-24T12:42:23")

(defun github-compare
    (arg)
  "Displays a github comparison link based on context.

When called from a file in a git project, it will find github
user associated with the current push branch and the github user
associated with the current upstream branch and display a link
comparing the two branches with the forks correctly
configured (like
https://github.com/<user>/<repo>/compare/master...timvisher:master?expand=1).

When called with an active commit range in any magit buffer, it
will display a compare link based on the current push branch's
fork and branch (like
https://github.com/<user>/<repo>/compare/88147f03..80873a45?expand=1),
assuming that the commits have all been pushed.

Any other context has undefined behavior."
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
         (maybe-range (let ((maybe-range (magit-diff--dwim)))
                        (if (and (stringp maybe-range)
                                 (not (string-suffix-p ".." maybe-range)))
                            maybe-range)))
         (comparison-component (if (stringp maybe-range)
                                   maybe-range
                                 (format
                                  ;; Base Branch like: master
                                  (concat "%s..."
                                          ;; Our github user like:
                                          ;; timvisher
                                          "%s:"
                                          ;; Our branch like:
                                          ;; feature/support-sierra
                                          "%s")
                                  base-branch
                                  our-user
                                  our-branch)))
         (compare-link (format
                        (concat "https://github.com/"
                                ;; Base User like: RJMetrics
                                "%s/"
                                ;; Project name like: boxcutter
                                "%s/"
                                "compare/"
                                ;; Comparison component like:
                                ;; 12341234...134124 or
                                ;; master...timvisher/feature/support-sierra
                                "%s?expand=1")
                        (if (stringp maybe-range)
                            our-user
                          base-user)
                        project-name
                        comparison-component)))

    ;; like https://github.com/RJMetrics/boxcutter/compare/master...timvisher:feature/support-sierra?expand=1
    (kill-new compare-link)
    (message "Saved %s to the kill ring" compare-link)
    (when (ide--prefix-arg-count-p arg 1)
      (browse-url compare-link))))

(defun github-commit-link
    (arg)
  (interactive "p")
  (let* ((remote-name (github-branch-to-remote-name
                       (or (magit-get-push-branch)
                           (magit-get-current-branch))))
         (remote-url (magit-get "remote" remote-name "url"))
         (project-name (github-url-to-repo-name remote-url))
         (github-user (github-url-to-user-name remote-url))
         (commit-hash (magit-rev-parse
                       (or (magit-branch-or-commit-at-point)
                           "HEAD")))
         (commit-link (format
                       (concat "https://github.com/"
                               ;; Push remote like: timvisher
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
      (progn
        ;; like: https://github.com/<user>/<repo>/commit/<commit hash>
        (kill-new commit-link)
        (message "Saved %s to the kill ring" commit-link)
        (when (ide--prefix-arg-count-p arg 1)
          (browse-url commit-link))))))

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

(defun zap-up-to-char-reverse
    (char)
  (interactive "cZap up to char (reverse): ")
  (zap-up-to-char -1 char))

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

(global-set-key (kbd "C-c C-j") 'imenu)

(global-set-key (kbd "M-Z") 'zap-up-to-char-reverse)

(eval-after-load 'projectile
  '(progn
     (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)))

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; org
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require 'org-tempo)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; magit
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar ide-magit-auto-status
  t
  "Whether or not to automatically open a magit-status buffer on startup")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Customize
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(put 'narrow-to-region 'disabled nil)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(Man-sed-command "gsed")
 '(auto-hscroll-mode 'current-line)
 '(cider-repl-use-pretty-printing t)
 '(cider-request-dispatch 'static)
 '(cider-test-defining-forms '("deftest" "defspec" "defn"))
 '(clojure-defun-indents '(fact facts for-all))
 '(coffee-tab-width 2)
 '(column-number-mode t)
 '(delete-selection-mode t)
 '(dired-dwim-target t)
 '(dired-recursive-copies 'always)
 '(erc-autojoin-timing 'ident)
 '(erc-server "irc.libera.chat")
 '(fill-column 74)
 '(global-auto-revert-mode t)
 '(global-hl-line-mode t)
 '(global-whitespace-mode nil)
 '(hippie-expand-try-functions-list
   '(try-complete-file-name-partially try-complete-file-name
                                      try-expand-all-abbrevs
                                      try-expand-dabbrev
                                      try-expand-dabbrev-all-buffers
                                      try-expand-dabbrev-from-kill
                                      try-complete-lisp-symbol-partially
                                      try-complete-lisp-symbol))
 '(ido-ubiquitous-mode t)
 '(ido-vertical-mode t)
 '(indent-tabs-mode nil)
 '(inhibit-startup-screen t)
 '(js-indent-level 2)
 '(langtool-http-server-host "localhost")
 '(langtool-http-server-port 8081)
 '(magit-branch-prefer-remote-upstream '("master" "main"))
 '(magit-diff-refine-hunk t)
 '(magit-process-connection-type nil)
 '(nrepl-use-ssh-fallback-for-remote-hosts t)
 '(org-adapt-indentation t)
 '(org-babel-clojure-backend 'cider)
 '(org-babel-load-languages '((emacs-lisp . t) (shell . t) (clojure . t)))
 '(org-export-backends '(ascii html latex md odt confluence gfm))
 '(org-export-copy-to-kill-ring 'if-interactive)
 '(org-export-initial-scope 'subtree)
 '(org-export-with-section-numbers nil)
 '(org-export-with-tags nil)
 '(org-export-with-toc nil)
 '(org-export-with-todo-keywords nil)
 '(org-html-postamble nil)
 '(org-html-style-default
   "<style>\12  #content { max-width: 60em; margin: auto; }\12  .title  { text-align: center;\12             margin-bottom: .2em; }\12  .subtitle { text-align: center;\12              font-size: medium;\12              font-weight: bold;\12              margin-top:0; }\12  .todo   { font-family: monospace; color: red; }\12  .done   { font-family: monospace; color: green; }\12  .priority { font-family: monospace; color: orange; }\12  .tag    { background-color: #eee; font-family: monospace;\12            padding: 2px; font-size: 80%; font-weight: normal; }\12  .timestamp { color: #555; }\12  .timestamp-kwd { color: #5f9ea0; }\12  .org-right  { margin-left: auto; margin-right: 0px;  text-align: right; }\12  .org-left   { margin-left: 0px;  margin-right: auto; text-align: left; }\12  .org-center { margin-left: auto; margin-right: auto; text-align: center; }\12  .underline { text-decoration: underline; }\12  #postamble p, #preamble p { font-size: 90%; margin: .2em; }\12  p.verse { margin-left: 3%; }\12  pre {\12    border: 1px solid #e6e6e6;\12    border-radius: 3px;\12    background-color: #f2f2f2;\12    padding: 8pt;\12    font-family: monospace;\12    overflow: auto;\12    margin: 1.2em;\12  }\12  pre.src {\12    position: relative;\12    overflow: auto;\12  }\12  pre.src:before {\12    display: none;\12    position: absolute;\12    top: -8px;\12    right: 12px;\12    padding: 3px;\12    color: #555;\12    background-color: #f2f2f299;\12  }\12  pre.src:hover:before { display: inline; margin-top: 14px;}\12  /* Languages per Org manual */\12  pre.src-asymptote:before { content: 'Asymptote'; }\12  pre.src-awk:before { content: 'Awk'; }\12  pre.src-authinfo::before { content: 'Authinfo'; }\12  pre.src-C:before { content: 'C'; }\12  /* pre.src-C++ doesn't work in CSS */\12  pre.src-clojure:before { content: 'Clojure'; }\12  pre.src-css:before { content: 'CSS'; }\12  pre.src-D:before { content: 'D'; }\12  pre.src-ditaa:before { content: 'ditaa'; }\12  pre.src-dot:before { content: 'Graphviz'; }\12  pre.src-calc:before { content: 'Emacs Calc'; }\12  pre.src-emacs-lisp:before { content: 'Emacs Lisp'; }\12  pre.src-fortran:before { content: 'Fortran'; }\12  pre.src-gnuplot:before { content: 'gnuplot'; }\12  pre.src-haskell:before { content: 'Haskell'; }\12  pre.src-hledger:before { content: 'hledger'; }\12  pre.src-java:before { content: 'Java'; }\12  pre.src-js:before { content: 'Javascript'; }\12  pre.src-latex:before { content: 'LaTeX'; }\12  pre.src-ledger:before { content: 'Ledger'; }\12  pre.src-lisp:before { content: 'Lisp'; }\12  pre.src-lilypond:before { content: 'Lilypond'; }\12  pre.src-lua:before { content: 'Lua'; }\12  pre.src-matlab:before { content: 'MATLAB'; }\12  pre.src-mscgen:before { content: 'Mscgen'; }\12  pre.src-ocaml:before { content: 'Objective Caml'; }\12  pre.src-octave:before { content: 'Octave'; }\12  pre.src-org:before { content: 'Org mode'; }\12  pre.src-oz:before { content: 'OZ'; }\12  pre.src-plantuml:before { content: 'Plantuml'; }\12  pre.src-processing:before { content: 'Processing.js'; }\12  pre.src-python:before { content: 'Python'; }\12  pre.src-R:before { content: 'R'; }\12  pre.src-ruby:before { content: 'Ruby'; }\12  pre.src-sass:before { content: 'Sass'; }\12  pre.src-scheme:before { content: 'Scheme'; }\12  pre.src-screen:before { content: 'Gnu Screen'; }\12  pre.src-sed:before { content: 'Sed'; }\12  pre.src-sh:before { content: 'shell'; }\12  pre.src-sql:before { content: 'SQL'; }\12  pre.src-sqlite:before { content: 'SQLite'; }\12  /* additional languages in org.el's org-babel-load-languages alist */\12  pre.src-forth:before { content: 'Forth'; }\12  pre.src-io:before { content: 'IO'; }\12  pre.src-J:before { content: 'J'; }\12  pre.src-makefile:before { content: 'Makefile'; }\12  pre.src-maxima:before { content: 'Maxima'; }\12  pre.src-perl:before { content: 'Perl'; }\12  pre.src-picolisp:before { content: 'Pico Lisp'; }\12  pre.src-scala:before { content: 'Scala'; }\12  pre.src-shell:before { content: 'Shell Script'; }\12  pre.src-ebnf2ps:before { content: 'ebfn2ps'; }\12  /* additional language identifiers per \"defun org-babel-execute\"\12       in ob-*.el */\12  pre.src-cpp:before  { content: 'C++'; }\12  pre.src-abc:before  { content: 'ABC'; }\12  pre.src-coq:before  { content: 'Coq'; }\12  pre.src-groovy:before  { content: 'Groovy'; }\12  /* additional language identifiers from org-babel-shell-names in\12     ob-shell.el: ob-shell is the only babel language using a lambda to put\12     the execution function name together. */\12  pre.src-bash:before  { content: 'bash'; }\12  pre.src-csh:before  { content: 'csh'; }\12  pre.src-ash:before  { content: 'ash'; }\12  pre.src-dash:before  { content: 'dash'; }\12  pre.src-ksh:before  { content: 'ksh'; }\12  pre.src-mksh:before  { content: 'mksh'; }\12  pre.src-posh:before  { content: 'posh'; }\12  /* Additional Emacs modes also supported by the LaTeX listings package */\12  pre.src-ada:before { content: 'Ada'; }\12  pre.src-asm:before { content: 'Assembler'; }\12  pre.src-caml:before { content: 'Caml'; }\12  pre.src-delphi:before { content: 'Delphi'; }\12  pre.src-html:before { content: 'HTML'; }\12  pre.src-idl:before { content: 'IDL'; }\12  pre.src-mercury:before { content: 'Mercury'; }\12  pre.src-metapost:before { content: 'MetaPost'; }\12  pre.src-modula-2:before { content: 'Modula-2'; }\12  pre.src-pascal:before { content: 'Pascal'; }\12  pre.src-ps:before { content: 'PostScript'; }\12  pre.src-prolog:before { content: 'Prolog'; }\12  pre.src-simula:before { content: 'Simula'; }\12  pre.src-tcl:before { content: 'tcl'; }\12  pre.src-tex:before { content: 'TeX'; }\12  pre.src-plain-tex:before { content: 'Plain TeX'; }\12  pre.src-verilog:before { content: 'Verilog'; }\12  pre.src-vhdl:before { content: 'VHDL'; }\12  pre.src-xml:before { content: 'XML'; }\12  pre.src-nxml:before { content: 'XML'; }\12  /* add a generic configuration mode; LaTeX export needs an additional\12     (add-to-list 'org-latex-listings-langs '(conf \" \")) in .emacs */\12  pre.src-conf:before { content: 'Configuration File'; }\12\12  table { border-collapse:collapse; }\12  caption.t-above { caption-side: top; }\12  caption.t-bottom { caption-side: bottom; }\12  td, th { vertical-align:top;  }\12  th.org-right  { text-align: center;  }\12  th.org-left   { text-align: center;   }\12  th.org-center { text-align: center; }\12  td.org-right  { text-align: right;  }\12  td.org-left   { text-align: left;   }\12  td.org-center { text-align: center; }\12  dt { font-weight: bold; }\12  .footpara { display: inline; }\12  .footdef  { margin-bottom: 1em; }\12  .figure { padding: 1em; }\12  .figure p { text-align: center; }\12  .equation-container {\12    display: table;\12    text-align: center;\12    width: 100%;\12  }\12  .equation {\12    vertical-align: middle;\12  }\12  .equation-label {\12    display: table-cell;\12    text-align: right;\12    vertical-align: middle;\12  }\12  .inlinetask {\12    padding: 10px;\12    border: 2px solid gray;\12    margin: 10px;\12    background: #ffffcc;\12  }\12  #org-div-home-and-up\12   { text-align: right; font-size: 70%; white-space: nowrap; }\12  textarea { overflow-x: auto; }\12  .linenr { font-size: smaller }\12  .code-highlighted { background-color: #ffff00; }\12  .org-info-js_info-navigation { border-style: none; }\12  #org-info-js_console-label\12    { font-size: 10px; font-weight: bold; white-space: nowrap; }\12  .org-info-js_search-highlight\12    { background-color: #ffff00; color: #000000; font-weight: bold; }\12  .org-svg { }\12</style>")
 '(org-log-done 'time)
 '(org-log-refile 'time)
 '(org-refile-allow-creating-parent-nodes 'confirm)
 '(org-refile-targets
   '((org-agenda-files :tag . "") ("todo.org" :maxlevel . 4)
     ("wiki.org" :maxlevel . 3)))
 '(org-refile-use-cache nil)
 '(org-refile-use-outline-path t)
 '(org-reverse-note-order t)
 '(org-startup-folded 'showeverything)
 '(org-todo-keywords
   '((sequence "TODO" "IN_PROGRESS" "|" "DONE" "CANCELLED")
     (sequence "DELEGATED" "|" "DONE" "CANCELLED")))
 '(org-use-property-inheritance '("EXPORT_OPTIONS"))
 '(package-selected-packages
   '(ag agent-shell bats-mode bazel better-defaults browse-kill-ring cider
        clojure-mode-extra-font-locking coffee-mode csv-mode
        dockerfile-mode eat edit-indirect expand-region fixme-mode go-mode
        htmlize ido-ubiquitous ido-vertical-mode inheritenv jq-mode
        langtool mediawiki org-contrib orgit outline-indent ox-slack
        paredit php-mode polymode projectile protobuf-mode sed-mode smex
        swift-mode terraform-mode typescript-mode vterm websocket xclip
        yaml-mode))
 '(package-vc-selected-packages
   '((claude-code :url "https://github.com/stevemolitor/claude-code.el")
     (monet :url "https://github.com/stevemolitor/monet")))
 '(projectile-mode t nil (projectile))
 '(python-check-command "pylint -f parseable")
 '(safe-local-variable-values
   '((sh-indent-for-case-alt . ++) (sh-indent-for-case-label . +)))
 '(search-default-mode 'char-fold-to-regexp)
 '(sentence-end-double-space nil)
 '(sh-basic-offset 2)
 '(tab-width 2)
 '(warning-suppress-types '((org-babel) (org-babel)))
 '(whitespace-line-column nil)
 '(whitespace-style
   '(face trailing tabs newline empty space-after-tab space-before-tab
          tab-mark))
 '(winner-mode t))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(match ((t (:inherit secondary-selection)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Load AI tooling
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun timvisher-load-op-environment-variables ()
  "Resolve 1Password secrets and update the current Emacs environment.

This function finds all environment variables whose values are
`op://` secret references, uses `op run` to resolve them, and
then updates the environment for the current Emacs session using
`setenv'.

It will signal an error if the `op` command fails or if any of
the secret references cannot be resolved."
  (interactive)
  ;; Define all the op:// references we need
  (let ((op-env-vars `(("OPENAI_API_KEY" . ,(or (getenv "OPENAI_API_KEY")
                                                "op://Private/OpenAI API Secret Key/credential"))
                       ("ANTHROPIC_API_KEY" . ,(or (getenv "ANTHROPIC_API_KEY")
                                                   "op://Private/Anthropic API Key/credential"))
                       ("GEMINI_API_KEY" . ,(or (getenv "GEMINI_API_KEY")
                                                "op://Private/Gemini API Key/credential"))
                       ("VERTEXAI_PROJECT" . ,(or (getenv "VERTEXAI_PROJECT")
                                                  "op://Private/Gemini API Key/Project number")))))

    ;; First, set all the op:// references in the environment
    (dolist (var-pair op-env-vars)
      (setenv (car var-pair) (cdr var-pair)))

    ;; Now use `op run` to resolve them all at once
    (with-temp-buffer
      (let ((exit-code (call-process-shell-command "op run --no-masking -- env" nil t)))
        (when (/= exit-code 0)
          (error "1Password command failed with exit code %d" exit-code)))

      ;; Process the output and update environment variables
      (goto-char (point-min))
      (let ((resolved-count 0))
        (while (re-search-forward "^\\([^=]+\\)=\\(.*\\)$" nil t)
          (let ((key (match-string 1))
                (val (match-string 2)))
            ;; Only update vars we care about and that got resolved (not still op://)
            (when (and (assoc key op-env-vars)
                      (not (string-prefix-p "op://" val)))
              (setenv key val)
              (setq resolved-count (1+ resolved-count)))))

        (if (= resolved-count (length op-env-vars))
            (message "Successfully loaded %d 1Password variable(s)." resolved-count)
          (error "Failed to resolve all 1Password secret references. Expected %d, got %d"
                 (length op-env-vars) resolved-count))))))

(dolist (p '("acp_el" "shell_maker" "agent_shell"))
  (if-let (p (getenv (format "timvisher_%s_checkout" p)))
      (progn
        (add-to-list 'load-path (directory-file-name p))
        (dolist (elc (directory-files p t "\\.elc\\'"))
          (delete-file elc)))))

(use-package agent-shell
  :ensure t
  :defer t
  :commands (agent-shell-anthropic-start-claude-code
             agent-shell-openai-start-codex)
  :bind ("C-c A" . agent-shell)
  :custom
  (agent-shell-session-strategy 'new)
  (agent-shell-cwd-function (lambda () command-line-default-directory))
  (agent-shell-preferred-agent-config 'claude-code)
  (agent-shell-file-completion-enabled nil)
  :init
  (setq agent-shell-mcp-servers
        '(((name . "homebrew")
           (command . "/opt/homebrew/bin/brew")
           (args . ("mcp-server"))
           (env . ()))))
  :config
  (setq acp-logging-enabled t)
  (setq agent-shell-logging-enabled t)

  ;; Load 1Password secrets for agent authentication
  (timvisher-load-op-environment-variables)

  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication
         :api-key (getenv "ANTHROPIC_API_KEY")))

  (setq agent-shell-openai-authentication
        (agent-shell-openai-make-authentication :api-key (getenv "OPENAI_API_KEY")))

  (setq agent-shell-google-authentication
        (agent-shell-google-make-authentication
         :api-key (getenv "GEMINI_API_KEY"))))

;; (use-package agent-shell-mcp-oauth
;;   :load-path "~/git/timvisher-dd/agent-shell-mcp-oauth/main"
;;   :after agent-shell)

(defun timvisher-EXP-claude-source-link ()
  "Copy a Claude-formatted source link for the current file/region.
Format: @/path/to/file:line or @/path/to/file:start-end

In dired buffers:
  - With active region: @ files in region (including partially enclosed)
  - With marked files: @ all marked files
  - Otherwise: @ file at point (resolving . and ..)

In regular file buffers:
  - On line 1 without region: @ whole file
  - With region on line 1: @ line 1 only
  - Otherwise: @ current line or region"
  (interactive)
  (cond
   ;; Handle dired buffers
   ((eq major-mode 'dired-mode)
    (let* ((files
            (cond
             ;; Active region: collect files in region
             ((use-region-p)
              (save-excursion
                (let ((start (region-beginning))
                      (end (region-end))
                      files)
                  (goto-char start)
                  (while (<= (point) end)
                    (when-let ((file (dired-get-filename nil t)))
                      (unless (member (file-name-nondirectory file) '("." ".."))
                        (push file files)))
                    (forward-line 1))
                  (nreverse files))))

             ;; Marked files exist
             ((save-excursion
                (goto-char (point-min))
                (re-search-forward dired-re-mark nil t))
              (dired-get-marked-files))

             ;; File at point
             (t
              (when-let ((file (dired-get-filename nil t)))
                (let ((basename (file-name-nondirectory file)))
                  (list (cond
                         ((string= basename ".") default-directory)
                         ((string= basename "..") (file-name-directory (directory-file-name default-directory)))
                         (t file))))))))
           (link (mapconcat (lambda (f) (format "@%s" f)) files "\n")))
      (if files
          (progn
            (kill-new link)
            (message "Copied to kill ring: %s" link))
        (error "No file at point"))))

   ;; Handle regular file buffers
   (t
    (let* ((file-path (buffer-file-name))
           (line-range (source-link--get-line-range))
           (start-line (plist-get line-range :start-line))
           (end-line (plist-get line-range :end-line))
           (link (cond
                  ;; Line 1 without region: @ whole file
                  ((and (= start-line 1) (= end-line 1) (not (use-region-p)))
                   (format "@%s" file-path))
                  ;; Range or single line with explicit selection
                  ((/= start-line end-line)
                   (format "@%s:%d-%d" file-path start-line end-line))
                  ;; Single line
                  (t
                   (format "@%s:%d" file-path start-line)))))
      (if file-path
          (progn
            (kill-new link)
            (message "Copied to kill ring: %s" link))
        (error "Buffer is not visiting a file"))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Load system extensions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(when (file-accessible-directory-p (ide--system-extension-theme-directory-name))
  (seq-doseq (directory-file (directory-files (ide--system-extension-theme-directory-name)
                                              nil
                                              "[^.]+"))
    (add-to-list 'custom-theme-load-path
                 (concat (ide--system-extension-theme-directory-name)
                         "/"
                         directory-file))
    (add-to-list 'load-path
                 (concat (ide--system-extension-theme-directory-name)
                         "/"
                         directory-file))))

(when (file-exists-p (ide--xdg-extension-directory-name))
  (add-to-list 'load-path (ide--xdg-extension-directory-name))
  (seq-map #'load-file
           (directory-files (ide--xdg-extension-directory-name) t "^[^.]")))

(put 'magit-clean 'disabled nil)

(require 'vc-git)

(when ide-magit-auto-status
  (when (vc-git-responsible-p default-directory)
   (magit-status)
   (delete-other-windows)))

(put 'scroll-left 'disabled nil)

(message "Started up in %.2f seconds" (float-time (time-subtract (current-time) startup-time)))
