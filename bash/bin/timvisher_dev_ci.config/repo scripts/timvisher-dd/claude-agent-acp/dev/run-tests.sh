#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)" || exit 1

echo "--- install ---"
npm ci || exit 1

echo "--- format:check ---"
npm run format:check || exit 1

echo "--- lint ---"
npm run lint || exit 1

echo "--- build (tsc) ---"
npm run build || exit 1

echo "--- test ---"
npm run test:run || exit 1
