#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)" || exit 1

echo "--- byte-compile ---"
emacs --batch -Q -L . \
  --eval "(setq byte-compile-error-on-warn t)" \
  -f batch-byte-compile \
  acp.el acp-fakes.el acp-traffic.el || exit 1

echo "--- test ---"
emacs --batch -Q -L . \
  -l tests/acp-test.el \
  -f ert-run-tests-batch-and-exit || exit 1
