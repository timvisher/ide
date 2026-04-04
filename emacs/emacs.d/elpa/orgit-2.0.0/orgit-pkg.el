;; -*- no-byte-compile: t; lexical-binding: nil -*-
(define-package "orgit" "2.0.0"
  "Support for Org links to Magit buffers."
  '((emacs  "26.1")
    (compat "30.0.0.0")
    (magit  "4.0.0")
    (org    "9.7.8"))
  :url "https://github.com/magit/orgit"
  :commit "59d21fdb21f84238c3172d37fdd2446b753e98dc"
  :revdesc "v2.0.0-0-g59d21fdb21f8"
  :keywords '("hypermedia" "vc")
  :authors '(("Jonas Bernoulli" . "emacs.orgit@jonas.bernoulli.dev"))
  :maintainers '(("Jonas Bernoulli" . "emacs.orgit@jonas.bernoulli.dev")))
