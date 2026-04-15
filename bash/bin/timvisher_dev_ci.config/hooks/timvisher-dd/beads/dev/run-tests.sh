#!/usr/bin/env bash

export PATH="$(brew --prefix)/bin:${PATH}"

cd "$(git rev-parse --show-toplevel)" || exit 1

echo "--- version-consistency ---"
scripts/check-versions.sh || exit 1

echo "--- fmt-check ---"
make fmt-check || exit 1

echo "--- lint ---"
golangci-lint run ./... --timeout=5m || exit 1

echo "--- test ---"
go test -v -race -short ./... || exit 1
