#!/usr/bin/env bash
# Repo rung hook: applies to every branch under xenodium/acp.el.
#
# acp.el is consumed by agent-shell as a plain upstream checkout, not a
# fork, so it carries no branches of ours and nothing to integrate. It is
# here to be pulled and verified before anything that depends on it is
# judged: an untested dependency bump surfaces as failures in the
# dependent repo and gets blamed on the dependent's own changes.

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
