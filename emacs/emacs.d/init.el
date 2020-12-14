;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Packages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
(add-to-list 'package-archives
             '("org" . "https://orgmode.org/elpa/")
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

(defun ide-python-insert-ipdb ()
  "Insert an ipdb breakpoint"
  (interactive)
  (insert "import ipdb; ipdb.set_trace()")
  (newline 1 t)
  (insert "1+1"))

(defun ide-schema-blank ()
  "Insert a barebones schema"
  (interactive)
  (insert "{
  \"type\": \"object\",
  \"properties\": {},
}"))

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
  (find-file (concat (getenv "HOME") "/.emacs.d/init.el")))

(defun ide--system-extension-theme-directory-name
    ()
  (concat (getenv "HOME")
          "/.emacs.d/host-extensions/"
          system-name
          "/themes"))

(defun ide--system-extension-file-name ()
  (concat (getenv "HOME")
          "/.emacs.d/host-extensions/"
          system-name
          ".el"))

(defun ide-edit-system-extension-file ()
  (interactive)
  (find-file (ide--system-extension-file-name)))

(defun paste-todo ()
  (interactive)
  (org-meta-return)
  (pbpaste))

(defvar ide-target-vm
  nil
  "The selected development VM for this emacs instance")

(setq ide-vms ["core" "taps" "core_aws"])

(setq ide-reachable-vms nil)

(defun ide--vm-host-is-reachable-p
    (host)
  "Test whether HOST can be reached via ssh"
  (if (= 0 (process-file-shell-command
            (format "ssh -o ConnectTimeout=2 -Tq '%s' true"
                    host)))
      (progn
        (message (format "%s is reachable"
                         host))
        t)
    (progn
      (message (format "%s is unreachable"
                       host))
      nil)))

(defun ide--get-reachable-vms
    (arg)
  (when (prefix-arg-count-p arg 1)
    (setq ide-reachable-vms nil))
  (unless ide-reachable-vms
    (setq ide-reachable-vms (or (seq-filter 'ide--vm-host-is-reachable-p ide-vms) [])))
  ide-reachable-vms)

(defun ide-read-target-vm
    (arg)
  (completing-read "Target VM: " (ide--get-reachable-vms arg)))

(defun ide-get-target-vm
    (arg)
  (if (or (prefix-arg-count-p arg 1)
          (not ide-target-vm)
          (not (seq-contains ide-vms ide-target-vm)))
      (setq ide-target-vm (ide-read-target-vm arg)))
  ide-target-vm)

(defun prefix-arg
    (count)
  (expt 4 count))

(defun ide-read-box-project
    (arg)
  (if (and (projectile-project-p)
           (yes-or-no-p (format "Use %s?" (abbreviate-file-name (projectile-project-root)))))
      ;; Should only be here temporarily while we migrate away from the
      ;; target vm concept
      (let* ((project-file (projectile-project-root))
             (remote-component (file-remote-p project-file)))
        (if remote-component
            (setq ide-target-vm (tramp-file-name-host (tramp-dissect-file-name remote-component)))
          nil)
        project-file)
    (let* ((box-files (seq-mapcat
                       (lambda (host)
                         (let ((host-base-directory
                                (format "/sshx:%s:/opt/code"
                                        host)))
                           (seq-map
                            (lambda (f)
                              (list (format "%s/%s" host f)
                                    (list host-base-directory f)))
                            (directory-files host-base-directory
                                             nil
                                             "^[^.]"))))
                       (ide--get-reachable-vms arg)))
           (host-files (seq-map (lambda (directory-file)
                                  (let ((git-dir (substring-no-properties directory-file 0 -5)))
                                    (list (abbreviate-file-name git-dir)
                                          (list "~/git" (file-relative-name git-dir "~/git")))))
                                (directory-files-recursively "~/git" "^\\.git$" t)))
           (all-files (seq-concatenate 'list box-files host-files))
           (files (sort (seq-map #'car all-files) 'string-lessp))
           (project (completing-read "Project: "
                                     files
                                     nil
                                     t))
           (project-file (cadr (assoc project all-files))))
      ;; Should only be here temporarily while we migrate away from the
      ;; target vm concept
      (let* ((project-dir (car project-file))
             (remote-component (file-remote-p project-dir)))
        (if remote-component
            (setq ide-target-vm (tramp-file-name-host (tramp-dissect-file-name remote-component)))
          nil))
      (format "%s/%s"
              (car project-file)
              (cadr project-file)))))

(defvar ide-read-box-project-cache nil)

(defun ide-read-box-project-or-cache
    (arg &optional var)
  (let ((var (or var 'ide-read-box-project-cache)))
    (if (or (prefix-arg-count-p arg 1) (not (symbol-value var)))
        (set var (ide-read-box-project arg))
      (symbol-value var))))

(defvar jump-to-project-cache nil)

(defun jump-to-project
    (arg)
  (interactive "p")
  (let* ((project (ide-read-box-project-or-cache arg)))
    (if project
        (dired project)
      (message "No project chosen"))))

(defun ide-find-file
    (arg)
  (interactive "p")
  (let ((default-directory (ide-read-box-project-or-cache arg)))
    (projectile-find-file (or (prefix-arg-count-p arg 1)
                              (prefix-arg-count-p arg 2)))))

(defun ide-find-alternative-file
    (arg)
  (interactive "p")
  (let ((default-directory (ide-read-box-project arg)))
    (projectile-find-file (or (prefix-arg-count-p arg 1)
                              (prefix-arg-count-p arg 2)))))

(defun ide-magit-project
    (arg)
  (interactive "p")
  (magit-status (ide-read-box-project-or-cache arg)))

(defun ide-magit-alternative-project
    (arg)
  (interactive "p")
  (magit-status (ide-read-box-project arg)))

(defun ide-dired-code-dir
    (arg)
  (interactive "p")
  (dired (format "/sshx:%s:/opt/code"
                 (ide-get-target-vm arg))))

(defun ide-dired-alternative-code-dir
    (arg)
  (interactive "p")
  (dired (format "/sshx:%s:/opt/code"
                 (ide-read-target-vm arg))))

(global-set-key (kbd "C-c C") 'ide-dired-code-dir)

(defun ide-clone-repo
    (github-username repository)
  (interactive "sYour GitHub username: \nsRepository name: ")
  (process-file "git"
                nil
                nil
                nil
                "clone"
                (format "git@github.com:stitchdata/%s.git" repository))
  (magit-status repository)
  ;; TODO cache github-username for the duration of the session or allow
  ;; it be customizod on a per host basis
  (magit-remote-add github-username
                    (format "git@github.com:%s/%s.git"
                            github-username
                            repository)))

(defun singer-clone-repo
    (github-username repository)
  (interactive "sGitHub username: \nsRepository name: ")
  (process-file "git"
                nil
                nil
                nil
                "clone"
                (format "git@github.com:singer-io/%s.git" repository))
  (magit-status repository)
  ;; TODO cache github-username for the duration of the session or allow
  ;; it be customizod on a per host basis
  (magit-remote-add github-username
                    (format "git@github.com:%s/%s.git"
                            github-username
                            repository)))

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
(define-obsolete-function-alias 'todo-frame-bounce 'ide-frame-bounce-todo)

(global-set-key (kbd "<f5>") 'ide-frame-bounce-todo)

(defun github-parse-remote-url
    (remote-url)
  "Returns an alist of user and repo"
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
                 ".git")
         remote-url)
      (error (format "%s is not on github.com" (buffer-file-name))))
    (append (list (list 'user (match-string-no-properties 1 remote-url)))
            (list (list 'repo
                        (match-string-no-properties 2 remote-url))))))

(defun github-browse-file-url
    ()
  (interactive)
  (let* ((file-path (magit-file-relative-name))
         (remote-url (magit-get "remote" (magit-get-remote) "url"))
         (parsed (github-parse-remote-url remote-url))
         (user (car (alist-get 'user parsed)))
         (repo (car (alist-get 'repo parsed)))
         (commit-hash (magit-rev-parse "HEAD"))
         ;; https://github.com/stitchdata/cloudcutter/blob/6d41fe1460b6e10ccebdf7c98021ac0f3db9bd2b/README.md
         (file-url (format "https://github.com/%s/%s/blob/%s/%s"
                           user
                           repo
                           commit-hash
                           file-path)))
    (message
     "%s"
     (url-encode-url file-url))))

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
  (when (magit-anything-modified-p)
    (error (concat "Cannot generate a source link as there "
                   "are modifications in the source tree.")))
  (let* ((remote-url (or (magit-get "remote" (magit-get-push-remote) "url")
                         (magit-get "remote" (magit-get-remote) "url")))
         (parsed (github-parse-remote-url remote-url))
         (user (car (alist-get 'user parsed)))
         (repo (car (alist-get 'repo parsed)))
         (commit-hash (if (prefix-arg-count-p arg 1)
                          (magit-get-current-branch)
                        (magit-rev-parse "HEAD")))
         (starting-line (line-number-at-pos (if (region-active-p)
                                                (region-beginning)
                                              (point))))
         (ending-line (line-number-at-pos (if (region-active-p)
                                              (region-end)
                                            (point))))
         (link (if (string-suffix-p ".md" (magit-file-relative-name))
                   (format "https://github.com/%s/%s/blob/%s/%s"
                           user
                           repo
                           commit-hash
                           (magit-file-relative-name))
                 (format "https://github.com/%s/%s/blob/%s/%s#L%d"
                         user
                         repo
                         commit-hash
                         (magit-file-relative-name)
                         starting-line)))
         (encoded-link (url-encode-url
                        (if (/= starting-line ending-line)
                            (format "%s-L%d" link ending-line)
                          link))))
    (kill-new encoded-link)
    (message "Saved %s to the kill ring"
             encoded-link)))

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
  (= count (ide--prefix-arg-count prefix-arg)))

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
https://github.com/stitchdata/boxcutter/compare/master...timvisher:master?expand=1).

When called with an active commit range in any magit buffer, it
will display a compare link based on the current push branch's
fork and branch (like
https://github.com/stitchdata/boxcutter/compare/88147f03..80873a45?expand=1),
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
      (progn
        ;; like: https://github.com/stitchdata/ide/commit/b9b11cc05baaf8383b2cc7968990a4fbf966c4a0
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

(defun ide-read-box-virtualenv
    (arg)
  (completing-read "virtualenv: "
                   (let ((target-vm (ide-get-target-vm arg)))
                     (seq-concatenate
                      'list
                      (directory-files (format "/sshx:%s:.virtualenvs"
                                               target-vm))
                      (directory-files (format "/sshx:%s:/usr/local/share/virtualenvs"
                                               target-vm))))
                   (lambda (file)
                     (not
                      (or (string= "." file)
                          (string= ".." file))))
                   t))

(defvar ide-virtualenv-base-dir nil)

(defun ide-virtualenv
    (arg)
  (interactive "p")
  (if (or (ide--prefix-arg-count-p arg 1) (not ide-virtualenv-base-dir))
      (setq ide-virtualenv-base-dir (ide-read-box-virtualenv arg)))
  (let ((base-dir (format "/home/vagrant/.virtualenvs/%s" ide-virtualenv-base-dir)))
    (setq python-shell-virtualenv-root base-dir)
    (message "python-shell-virtualenv-root=%s" base-dir)))

(defun ide-get-org-timestamp-string
    ()
  (format-time-string "<%F %a %H:%M>"))

(defun ide-org-set-ctime
    (&optional ctime)
  (interactive)
  (let ((ctime (if (not ctime)
                   (ide-get-org-timestamp-string)
                 ctime)))
    (if (org-entry-get (point) "CREATED_AT")
        (message "Entry already has CREATED_AT: %s"
                 (org-entry-get (point) "CREATED_AT"))
      (progn
        (org-entry-put (point)
                       "CREATED_AT"
                       ctime)
        (message "Set entry CREATED_AT to %s"
                 ctime)))))

(defun ide-org-set-mtime
    ()
  (interactive)
  (let ((mtime (ide-get-org-timestamp-string)))
    (ide-org-set-ctime mtime)
    (if (org-entry-get (point) "MODIFIED_AT")
        (let ((current-mtime (org-entry-get (point) "MODIFIED_AT")))
          (org-entry-put (point)
                         "MODIFIED_AT"
                         mtime)
          (message "Changed entry MODIFIED_AT from %s → %s"
                   current-mtime
                   mtime))
      (progn
        (org-entry-put (point)
                       "MODIFIED_AT"
                       mtime)
        (message "Set entry MODIFIED_AT to %s"
                 mtime)))))

(defun ide-swap-light-and-dark
    ()
  (interactive)
  (if (eq 'light frame-background-mode)
      (setq frame-background-mode 'dark)
    (setq frame-background-mode 'light))
  (frame-set-background-mode nil)
  (message "Set frame-background-mode to %s" frame-background-mode))


(defun zap-up-to-char-reverse
    (char)
  (interactive "cZap up to char (reverse): ")
  (zap-up-to-char -1 char))

(defun ide-ag-project
    (arg)
  (interactive "p")
  (let ((default-directory (ide-read-box-project-or-cache arg)))
    (call-interactively 'ag-project)))

(defun ide-ag-alternative-project
    (arg)
  (interactive "p")
  (let ((default-directory (ide-read-box-project arg)))
    (call-interactively 'ag-project)))

(defun ide-ag-code-dir
    (arg string)
  "Runs ag inside the code directory on the VM"
  (interactive (list (prefix-numeric-value current-prefix-arg)
                     (ag/read-from-minibuffer "Search string")))
  (let ((target-vm (if (< 0 (ide--prefix-arg-count arg))
                       (ide-get-target-vm 4)
                     (ide-get-target-vm 1)))
        (current-prefix-arg (ide--prefix-arg-count-p arg 2)))
    (ag string (format "/sshx:%s:/opt/code/"
                       target-vm))))

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

(global-set-key (kbd "C-c A") 'ide-ag-project)

(global-set-key (kbd "C-c a p") 'ide-ag-project)

(autoload 'ag/read-from-minibuffer "ag")

(global-set-key (kbd "C-c a c") 'ide-ag-code-dir)

(global-set-key (kbd "C-c P") 'ide-find-file)

(global-set-key (kbd "C-c G") 'ide-magit-project)

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Customize
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(put 'narrow-to-region 'disabled nil)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ag-arguments
   '("--line-number" "--smart-case" "--nogroup" "--column" "--stats" "--hidden" "--"))
 '(auto-hscroll-mode 'current-line)
 '(cider-repl-use-pretty-printing t)
 '(cider-request-dispatch 'static)
 '(clojure-defun-indents '(fact facts for-all))
 '(coffee-tab-width 2)
 '(column-number-mode t)
 '(delete-selection-mode t)
 '(dired-dwim-target t)
 '(dired-recursive-copies 'always)
 '(fill-column 74)
 '(global-hl-line-mode t)
 '(global-whitespace-mode nil)
 '(hippie-expand-try-functions-list
   '(try-complete-file-name-partially try-complete-file-name try-expand-all-abbrevs try-expand-dabbrev try-expand-dabbrev-all-buffers try-expand-dabbrev-from-kill try-complete-lisp-symbol-partially try-complete-lisp-symbol))
 '(ido-ubiquitous-mode t)
 '(ido-vertical-mode t)
 '(js-indent-level 2)
 '(magit-diff-refine-hunk t)
 '(nrepl-use-ssh-fallback-for-remote-hosts t)
 '(org-export-backends '(ascii html md))
 '(org-export-initial-scope 'subtree)
 '(org-export-with-section-numbers nil)
 '(org-export-with-tags nil)
 '(org-export-with-toc nil)
 '(org-export-with-todo-keywords nil)
 '(org-log-done 'time)
 '(org-log-refile 'time)
 '(org-refile-allow-creating-parent-nodes 'confirm)
 '(org-refile-targets '((nil :maxlevel . 3)))
 '(org-refile-use-outline-path t)
 '(org-reverse-note-order t)
 '(org-todo-keywords
   '((sequence "TODO" "IN_PROGRESS" "|" "DONE" "CANCELLED")
     (sequence "DELEGATED" "|" "DONE" "CANCELLED")))
 '(org-use-property-inheritance '("EXPORT_OPTIONS"))
 '(package-selected-packages
   '(dockerfile-mode cider clojure-mode go-mode ido-completing-read+ browse-kill-ring xclip htmlize hcl-mode align-cljlet org mediawiki coffee-mode yaml-mode smex projectile paredit markdown-mode magit ido-vertical-mode ido-ubiquitous fixme-mode expand-region better-defaults bats-mode ag terraform-mode coffee-mode php-mode))
 '(projectile-mode t nil (projectile))
 '(python-check-command "pylint -f parseable")
 '(safe-local-variable-values
   '((sh-indent-for-case-alt . ++)
     (sh-indent-for-case-label . +)))
 '(search-default-mode 'char-fold-to-regexp)
 '(sentence-end-double-space nil)
 '(sh-basic-offset 2)
 '(whitespace-line-column nil)
 '(whitespace-style
   '(face trailing tabs newline empty space-after-tab space-before-tab tab-mark))
 '(winner-mode t))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(secondary-selection ((t (:extend t :background "yellow1" :foreground "white")))))

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

(when (file-exists-p (ide--system-extension-file-name))
  (load (ide--system-extension-file-name)))

(put 'magit-clean 'disabled nil)
