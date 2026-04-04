#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)" || exit 1

echo "--- vet ---"
go vet -all ./... || exit 1

echo "--- golangci-lint ---"
golangci-lint run ./... || exit 1

echo "--- fmt check ---"
if [[ -n "$(gofmt -l .)" ]]
then
  echo "The following files are not formatted:"
  gofmt -l .
  exit 1
fi

echo "--- test ---"
go test -v ./... || exit 1

echo "--- all checks passed ---"
