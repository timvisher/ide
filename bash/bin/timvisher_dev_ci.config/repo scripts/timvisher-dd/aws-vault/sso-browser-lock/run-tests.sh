#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)" || exit 1

echo "--- vet ---"
make vet || exit 1

echo "--- test ---"
make test || exit 1
