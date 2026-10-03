#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)" || exit

export CLAUDE_CODE_EXECUTABLE=/usr/bin/false

echo "--- install ---"
npm ci || exit

echo "--- lint ---"
npm run lint || exit

echo "--- format check ---"
npm run format:check || exit

echo "--- type check / build ---"
npm run build || exit

echo "--- test ---"
npm run test:run || exit
