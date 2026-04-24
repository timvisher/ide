#!/usr/bin/env bash

export PATH="$(brew --prefix)/bin:${PATH}"

cd "$(git rev-parse --show-toplevel)" || exit 1

# Canonical build flags: sets GOFLAGS=-tags=gms_pure_go so golangci-lint and
# go test skip the ICU-backed regex path (unicode/regex.h isn't installed).
# Guarded — a missing or unreadable .buildflags would silently drop GOFLAGS
# and cause confusing downstream failures (ICU regex compile errors).
if [[ ! -r .buildflags ]]
then
  echo "FATAL: .buildflags not found at $(pwd); cannot set GOFLAGS" >&2
  exit 1
fi
# shellcheck source=/dev/null
source .buildflags

# scripts/test.sh default is 3m, but ./cmd/bd/ alone takes ~3.5m.
export TEST_TIMEOUT="${TEST_TIMEOUT:-15m}"

echo "--- version-consistency ---"
scripts/check-versions.sh || exit 1

echo "--- fmt-check ---"
make fmt-check || exit 1

echo "--- lint ---"
golangci-lint run ./... --timeout=5m || exit 1

echo "--- test ---"
make test || exit 1
