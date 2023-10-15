(define-package "cider" "1.8.0" "Clojure Interactive Development Environment that Rocks"
  '((emacs "26")
    (clojure-mode "5.17.1")
    (parseedn "1.2.0")
    (queue "0.2")
    (spinner "1.7")
    (seq "2.22")
    (sesman "0.3.2")
    (transient "0.4.1"))
  :commit "e9936f52432d25fdb2477dc4ec8fe95a7806e784" :authors
  '(("Tim King" . "kingtim@gmail.com")
    ("Phil Hagelberg" . "technomancy@gmail.com")
    ("Bozhidar Batsov" . "bozhidar@batsov.dev")
    ("Artur Malabarba" . "bruce.connor.am@gmail.com")
    ("Hugo Duncan" . "hugo@hugoduncan.org")
    ("Steve Purcell" . "steve@sanityinc.com"))
  :maintainers
  '(("Bozhidar Batsov" . "bozhidar@batsov.dev"))
  :maintainer
  '("Bozhidar Batsov" . "bozhidar@batsov.dev")
  :keywords
  '("languages" "clojure" "cider")
  :url "http://www.github.com/clojure-emacs/cider")
;; Local Variables:
;; no-byte-compile: t
;; End:
