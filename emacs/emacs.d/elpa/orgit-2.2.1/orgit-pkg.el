;; -*- no-byte-compile: t; lexical-binding: nil -*-
(define-package "orgit" "2.2.1"
  "Support for Org links to Magit buffers."
  '((emacs    "29.1")
    (compat   "31.0")
    (cond-let "1.1")
    (llama    "1.0")
    (magit    "4.7")
    (org      "9.8"))
  :url "https://github.com/magit/orgit"
  :commit "c948819a7cad37a654ada275ebf7c003abf782d0"
  :revdesc "v2.2.1-0-gc948819a7cad"
  :keywords '("hypermedia" "vc")
  :authors '(("Jonas Bernoulli" . "emacs.orgit@jonas.bernoulli.dev"))
  :maintainers '(("Jonas Bernoulli" . "emacs.orgit@jonas.bernoulli.dev")))
