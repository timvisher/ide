(require 'package)
(unless (assoc "gnu" package-archives)
  (add-to-list 'package-archives
               '("gnu" . "https://elpa.gnu.org/packages/")
               t))
(package-initialize)

(unless (require 'use-package nil t)
  (package-refresh-contents)
  (package-install 'use-package)
  (require 'use-package))

(use-package paredit
  :ensure t)

(defun lisp-editing--assert-elisp-mode ()
  (unless (eq major-mode 'emacs-lisp-mode)
    (error "Expected emacs-lisp-mode, got %S" major-mode)))

(add-hook 'find-file-hook #'lisp-editing--assert-elisp-mode)
(add-hook 'emacs-lisp-mode-hook #'paredit-mode)

(defun lisp-editing--pop-edit-program ()
  (let ((edit-program (pop command-line-args-left)))
    (when (null edit-program)
      (error "Missing edit program"))
    (setq command-line-args-left nil)
    edit-program))

(defun agent-run ()
  (let ((edit-program (lisp-editing--pop-edit-program)))
    (load-file edit-program)
    (save-buffer)))
