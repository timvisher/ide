#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

echo "--- install ---"
npm ci

echo "--- lint ---"
npm run lint

echo "--- format check ---"
npm run format:check

echo "--- type check / build ---"
npm run build

echo "--- test ---"
npm run test:run
