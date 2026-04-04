#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)"

echo "--- build ---"
make build
