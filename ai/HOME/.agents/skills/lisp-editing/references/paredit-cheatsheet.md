# Paredit Cheatsheet

Source: `references/paredit.pdf` (examples generated from paredit.el v26).

Notation: `|` marks the initial cursor position in the file examples and the final cursor position in result examples; it is not literal file content.
Program snippets use a numeric `goto-char` based on the marker in the file example.

## Basic Insertion Commands

### paredit-open-round

#### Example 1

file:
```text
(a b |c d)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-open-round))
```

result:
```text
(a b (|) c d)
```

#### Example 2

file:
```text
(foo "bar |baz" quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-open-round))
```

result:
```text
(foo "bar (|baz" quux)
```

### paredit-close-round

#### Example 1

file:
```text
(a b |c   )
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-close-round))
```

result:
```text
(a b c)|
```

#### Example 2

file:
```text
; Hello,| world!
```

program:
```elisp
(progn
  (goto-char 9)
  (paredit-close-round))
```

result:
```text
; Hello,)| world!
```

### paredit-close-round-and-newline

#### Example 1

file:
```text
(defun f (x|  ))
```

program:
```elisp
(progn
  (goto-char 12)
  (paredit-close-round-and-newline))
```

result:
```text
(defun f (x)
  |)
```

#### Example 2

file:
```text
; (Foo.|
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-close-round-and-newline))
```

result:
```text
; (Foo.)|
```

### paredit-open-square

#### Example 1

file:
```text
(a b |c d)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-open-square))
```

result:
```text
(a b [|] c d)
```

#### Example 2

file:
```text
(foo "bar |baz" quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-open-square))
```

result:
```text
(foo "bar [|baz" quux)
```

### paredit-close-square

#### Example 1

file:
```text
(define-key keymap [frob|  ] 'frobnicate)
```

program:
```elisp
(progn
  (goto-char 25)
  (paredit-close-square))
```

result:
```text
(define-key keymap [frob]| 'frobnicate)
```

#### Example 2

file:
```text
; [Bar.|
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-close-square))
```

result:
```text
; [Bar.]|
```

### paredit-doublequote

#### Example 1

file:
```text
(frob grovel |full lexical)
```

program:
```elisp
(progn
  (goto-char 14)
  (paredit-doublequote))
```

result:
```text
(frob grovel "|" full lexical)
```

#### Example 2

file:
```text
(frob grovel "|" full lexical)
```

program:
```elisp
(progn
  (goto-char 15)
  (paredit-doublequote))
```

result:
```text
(frob grovel ""| full lexical)
```

#### Example 3

file:
```text
(foo "bar |baz" quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-doublequote))
```

result:
```text
(foo "bar \"|baz" quux)
```

#### Example 4

file:
```text
(frob grovel)   ; full |lexical
```

program:
```elisp
(progn
  (goto-char 24)
  (paredit-doublequote))
```

result:
```text
(frob grovel)   ; full "|lexical
```

### paredit-meta-doublequote

#### Example 1

file:
```text
(foo "bar |baz" quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-meta-doublequote))
```

result:
```text
(foo "bar baz"| quux)
```

#### Example 2

file:
```text
(foo |(bar #\x "baz \\ quux") zot)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-meta-doublequote))
```

result:
```text
(foo "|(bar #\\x \"baz \\\\ quux\")" zot)
```

### paredit-backslash

#### Example 1

file:
```text
(string #|)
  ; Character to escape: x
```

program:
```elisp
(progn
  (goto-char 10)
  (paredit-backslash))
```

result:
```text
(string #\x|)
```

#### Example 2

file:
```text
"foo|bar"
  ; Character to escape: "
```

program:
```elisp
(progn
  (goto-char 5)
  (paredit-backslash))
```

result:
```text
"foo\"|bar"
```

### paredit-semicolon

#### Example 1

file:
```text
|(frob grovel)
```

program:
```elisp
(progn
  (goto-char 1)
  (paredit-semicolon))
```

result:
```text
;|(frob grovel)
```

#### Example 2

file:
```text
(frob |grovel)
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-semicolon))
```

result:
```text
(frob ;|grovel
 )
```

#### Example 3

file:
```text
(frob |grovel (bloit
               zargh))
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-semicolon))
```

result:
```text
(frob ;|grovel
 (bloit
  zargh))
```

#### Example 4

file:
```text
(frob grovel)          |
```

program:
```elisp
(progn
  (goto-char 24)
  (paredit-semicolon))
```

result:
```text
(frob grovel)          ;|
```

### paredit-comment-dwim

#### Example 1

file:
```text
(foo |bar)   ; baz
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-comment-dwim))
```

result:
```text
(foo bar)                               ; |baz
```

#### Example 2

file:
```text
(frob grovel)|
```

program:
```elisp
(progn
  (goto-char 14)
  (paredit-comment-dwim))
```

result:
```text
(frob grovel)                           ;|
```

#### Example 3

file:
```text
(zot (foo bar)
|
     (baz quux))
```

program:
```elisp
(progn
  (goto-char 16)
  (paredit-comment-dwim))
```

result:
```text
(zot (foo bar)
     ;; |
     (baz quux))
```

#### Example 4

file:
```text
(zot (foo bar) |(baz quux))
```

program:
```elisp
(progn
  (goto-char 16)
  (paredit-comment-dwim))
```

result:
```text
(zot (foo bar)
     ;; |
     (baz quux))
```

#### Example 5

file:
```text
|(defun hello-world ...)
```

program:
```elisp
(progn
  (goto-char 1)
  (paredit-comment-dwim))
```

result:
```text
;;; |
(defun hello-world ...)
```

### paredit-newline

#### Example 1

file:
```text
(let ((n (frobbotz))) |(display (+ n 1)
port))
```

program:
```elisp
(progn
  (goto-char 23)
  (paredit-newline))
```

result:
```text
(let ((n (frobbotz)))
  |(display (+ n 1)
           port))
```

## Deleting & Killing

### paredit-forward-delete

#### Example 1

file:
```text
(quu|x "zot")
```

program:
```elisp
(progn
  (goto-char 5)
  (paredit-forward-delete))
```

result:
```text
(quu| "zot")
```

#### Example 2

file:
```text
(quux |"zot")
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-forward-delete))
```

result:
```text
(quux "|zot")
```

#### Example 3

file:
```text
(quux "|zot")
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-forward-delete))
```

result:
```text
(quux "|ot")
```

#### Example 4

file:
```text
(foo (|) bar)
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-forward-delete))
```

result:
```text
(foo | bar)
```

#### Example 5

file:
```text
|(foo bar)
```

program:
```elisp
(progn
  (goto-char 1)
  (paredit-forward-delete))
```

result:
```text
(|foo bar)
```

### paredit-backward-delete

#### Example 1

file:
```text
("zot" q|uux)
```

program:
```elisp
(progn
  (goto-char 9)
  (paredit-backward-delete))
```

result:
```text
("zot" |uux)
```

#### Example 2

file:
```text
("zot"| quux)
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-backward-delete))
```

result:
```text
("zot|" quux)
```

#### Example 3

file:
```text
("zot|" quux)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-backward-delete))
```

result:
```text
("zo|" quux)
```

#### Example 4

file:
```text
(foo (|) bar)
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-backward-delete))
```

result:
```text
(foo | bar)
```

#### Example 5

file:
```text
(foo bar)|
```

program:
```elisp
(progn
  (goto-char 10)
  (paredit-backward-delete))
```

result:
```text
(foo bar|)
```

### paredit-delete-char

#### Example 1

file:
```text
(quu|x "zot")
```

program:
```elisp
(progn
  (goto-char 5)
  (paredit-delete-char))
```

result:
```text
(quu| "zot")
```

#### Example 2

file:
```text
(quux |"zot")
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-delete-char))
```

result:
```text
(quux "|zot")
```

#### Example 3

file:
```text
(quux "|zot")
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-delete-char))
```

result:
```text
(quux "|ot")
```

#### Example 4

file:
```text
(foo (|) bar)
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-delete-char))
```

result:
```text
(foo | bar)
```

#### Example 5

file:
```text
|(foo bar)
```

program:
```elisp
(progn
  (goto-char 1)
  (paredit-delete-char))
```

result:
```text
(|foo bar)
```

### paredit-kill

#### Example 1

file:
```text
(foo bar)|     ; Useless comment!
```

program:
```elisp
(progn
  (goto-char 10)
  (paredit-kill))
```

result:
```text
(foo bar)|
```

#### Example 2

file:
```text
(|foo bar)     ; Useful comment!
```

program:
```elisp
(progn
  (goto-char 2)
  (paredit-kill))
```

result:
```text
(|)     ; Useful comment!
```

#### Example 3

file:
```text
|(foo bar)     ; Useless line!
```

program:
```elisp
(progn
  (goto-char 1)
  (paredit-kill))
```

result:
```text
|
```

#### Example 4

file:
```text
(foo "|bar baz"
     quux)
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-kill))
```

result:
```text
(foo "|"
     quux)
```

### paredit-forward-kill-word

#### Example 1

file:
```text
|(foo bar)    ; baz
```

program:
```elisp
(progn
  (goto-char 1)
  (paredit-forward-kill-word))
```

result:
```text
(| bar)    ; baz
```

#### Example 2

file:
```text
(| bar)    ; baz
```

program:
```elisp
(progn
  (goto-char 2)
  (paredit-forward-kill-word))
```

result:
```text
(|)    ; baz
```

#### Example 3

file:
```text
(|)    ; baz
```

program:
```elisp
(progn
  (goto-char 2)
  (paredit-forward-kill-word))
```

result:
```text
()    ;|
```

#### Example 4

file:
```text
;;;| Frobnicate
(defun frobnicate ...)
```

program:
```elisp
(progn
  (goto-char 4)
  (paredit-forward-kill-word))
```

result:
```text
;;;|
(defun frobnicate ...)
```

#### Example 5

file:
```text
;;;|
(defun frobnicate ...)
```

program:
```elisp
(progn
  (goto-char 4)
  (paredit-forward-kill-word))
```

result:
```text
;;;
(| frobnicate ...)
```

### paredit-backward-kill-word

#### Example 1

file:
```text
(foo bar)    ; baz
(quux)|
```

program:
```elisp
(progn
  (goto-char 26)
  (paredit-backward-kill-word))
```

result:
```text
(foo bar)    ; baz
(|)
```

#### Example 2

file:
```text
(foo bar)    ; baz
(|)
```

program:
```elisp
(progn
  (goto-char 21)
  (paredit-backward-kill-word))
```

result:
```text
(foo bar)    ; |
()
```

#### Example 3

file:
```text
(foo bar)    ; |
()
```

program:
```elisp
(progn
  (goto-char 16)
  (paredit-backward-kill-word))
```

result:
```text
(foo |)    ; 
()
```

#### Example 4

file:
```text
(foo |)    ; 
()
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-backward-kill-word))
```

result:
```text
(|)    ; 
()
```

## Movement & Navigation

### paredit-forward

#### Example 1

file:
```text
(foo |(bar baz) quux)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-forward))
```

result:
```text
(foo (bar baz)| quux)
```

#### Example 2

file:
```text
(foo (bar)|)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-forward))
```

result:
```text
(foo (bar))|
```

### paredit-backward

#### Example 1

file:
```text
(foo (bar baz)| quux)
```

program:
```elisp
(progn
  (goto-char 15)
  (paredit-backward))
```

result:
```text
(foo |(bar baz) quux)
```

#### Example 2

file:
```text
(|(foo) bar)
```

program:
```elisp
(progn
  (goto-char 2)
  (paredit-backward))
```

result:
```text
|((foo) bar)
```

## Depth-Changing Commands

### paredit-wrap-round

#### Example 1

file:
```text
(foo |bar baz)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-wrap-round))
```

result:
```text
(foo (|bar) baz)
```

### paredit-splice-sexp

#### Example 1

file:
```text
(foo (bar| baz) quux)
```

program:
```elisp
(progn
  (goto-char 10)
  (paredit-splice-sexp))
```

result:
```text
(foo bar| baz quux)
```

### paredit-splice-sexp-killing-backward

#### Example 1

file:
```text
(foo (let ((x 5)) |(sqrt n)) bar)
```

program:
```elisp
(progn
  (goto-char 19)
  (paredit-splice-sexp-killing-backward))
```

result:
```text
(foo |(sqrt n) bar)
```

### paredit-splice-sexp-killing-forward

#### Example 1

file:
```text
(a (b c| d e) f)
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-splice-sexp-killing-forward))
```

result:
```text
(a b c| f)
```

### paredit-raise-sexp

#### Example 1

file:
```text
(dynamic-wind in (lambda () |body) out)
```

program:
```elisp
(progn
  (goto-char 29)
  (paredit-raise-sexp))
```

result:
```text
(dynamic-wind in |body out)
```

#### Example 2

file:
```text
(dynamic-wind in |body out)
```

program:
```elisp
(progn
  (goto-char 18)
  (paredit-raise-sexp))
```

result:
```text
|body
```

### paredit-convolute-sexp

#### Example 1

file:
```text
(let ((x 5) (y 3)) (frob |(zwonk)) (wibblethwop))
```

program:
```elisp
(progn
  (goto-char 26)
  (paredit-convolute-sexp))
```

result:
```text
(frob |(let ((x 5) (y 3)) (zwonk) (wibblethwop)))
```

## Barfage & Slurpage

### paredit-forward-slurp-sexp

#### Example 1

file:
```text
(foo (bar |baz) quux zot)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-forward-slurp-sexp))
```

result:
```text
(foo (bar |baz quux) zot)
```

#### Example 2

file:
```text
(a b ((c| d)) e f)
```

program:
```elisp
(progn
  (goto-char 9)
  (paredit-forward-slurp-sexp))
```

result:
```text
(a b ((c| d) e) f)
```

### paredit-forward-barf-sexp

#### Example 1

file:
```text
(foo (bar |baz quux) zot)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-forward-barf-sexp))
```

result:
```text
(foo (bar |baz) quux zot)
```

### paredit-backward-slurp-sexp

#### Example 1

file:
```text
(foo bar (baz| quux) zot)
```

program:
```elisp
(progn
  (goto-char 14)
  (paredit-backward-slurp-sexp))
```

result:
```text
(foo (bar baz| quux) zot)
```

#### Example 2

file:
```text
(a b ((c| d)) e f)
```

program:
```elisp
(progn
  (goto-char 9)
  (paredit-backward-slurp-sexp))
```

result:
```text
(a (b (c| d)) e f)
```

### paredit-backward-barf-sexp

#### Example 1

file:
```text
(foo (bar baz |quux) zot)
```

program:
```elisp
(progn
  (goto-char 15)
  (paredit-backward-barf-sexp))
```

result:
```text
(foo bar (baz |quux) zot)
```

## Miscellaneous Commands

### paredit-split-sexp

#### Example 1

file:
```text
(hello| world)
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-split-sexp))
```

result:
```text
(hello)| (world)
```

#### Example 2

file:
```text
"Hello, |world!"
```

program:
```elisp
(progn
  (goto-char 9)
  (paredit-split-sexp))
```

result:
```text
"Hello, "| "world!"
```

### paredit-join-sexps

#### Example 1

file:
```text
(hello)| (world)
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-join-sexps))
```

result:
```text
(hello| world)
```

#### Example 2

file:
```text
"Hello, "| "world!"
```

program:
```elisp
(progn
  (goto-char 10)
  (paredit-join-sexps))
```

result:
```text
"Hello, |world!"
```

#### Example 3

file:
```text
hello-
|  world
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-join-sexps))
```

result:
```text
hello-|world
```

## Additional examples (not in paredit-commands)

### paredit-forward-down

file:
```text
(foo |(bar baz) quux)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-forward-down))
```

result:
```text
(foo (|bar baz) quux)
```

### paredit-backward-down

file:
```text
(foo (bar baz)| quux)
```

program:
```elisp
(progn
  (goto-char 15)
  (paredit-backward-down))
```

result:
```text
(foo (bar baz|) quux)
```

### paredit-forward-up

file:
```text
(foo (bar |baz) quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-forward-up))
```

result:
```text
(foo (bar baz)| quux)
```

### paredit-backward-up

file:
```text
(foo (bar |baz) quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-backward-up))
```

result:
```text
(foo |(bar baz) quux)
```

### paredit-RET

file:
```text
(foo |bar baz)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-RET))
```

result:
```text
(foo
 |bar baz)
```

### paredit-C-j

file:
```text
(foo |bar baz)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-C-j))
```

result:
```text
(foo 
|bar baz)
```

### paredit-reindent-defun

file:
```text
(defun foo ()
|(list 1
 2))
```

program:
```elisp
(progn
  (goto-char 15)
  (paredit-reindent-defun))
```

result:
```text
(defun foo ()
|(list 1
      2))
```

### paredit-add-to-previous-list

file:
```text
((a b) |(c d))
```

program:
```elisp
(progn
  (goto-char 8)
  (paredit-add-to-previous-list))
```

result:
```text
((a b |(c d)))
```

### paredit-add-to-next-list

file:
```text
((a b)| (c d))
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-add-to-next-list))
```

result:
```text
(((a b)| c d))
```

### paredit-join-with-previous-list

file:
```text
((a b) (|c d))
```

program:
```elisp
(progn
  (goto-char 9)
  (paredit-join-with-previous-list))
```

result:
```text
((a b |c d))
```

### paredit-join-with-next-list

file:
```text
((a b)| (c d))
```

program:
```elisp
(progn
  (goto-char 7)
  (paredit-join-with-next-list))
```

result:
```text
((a b| c d))
```

### paredit-wrap-sexp

file:
```text
(foo |bar baz)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-wrap-sexp))
```

result:
```text
(foo (|bar) baz)
```

### paredit-wrap-square

file:
```text
(foo |bar baz)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-wrap-square))
```

result:
```text
(foo [|bar] baz)
```

### paredit-wrap-curly

file:
```text
(foo |bar baz)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-wrap-curly))
```

result:
```text
(foo {|bar} baz)
```

### paredit-wrap-angled

file:
```text
(foo |bar baz)
```

program:
```elisp
(progn
  (goto-char 6)
  (paredit-wrap-angled))
```

result:
```text
(foo <|bar> baz)
```

### paredit-meta-doublequote-and-newline

file:
```text
(foo "bar |baz" quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-meta-doublequote-and-newline))
```

result:
```text
(foo "bar baz"
     |quux)
```

### paredit-splice-string

file:
```text
(foo "bar |baz" quux)
```

program:
```elisp
(progn
  (goto-char 11)
  (paredit-splice-string nil))
```

result:
```text
(foo bar |baz quux)
```
