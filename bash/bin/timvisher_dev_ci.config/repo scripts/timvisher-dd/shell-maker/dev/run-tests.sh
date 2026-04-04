#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)" || exit 1

el_files=(shell-maker.el markdown-overlays.el)

echo "--- byte-compile ---"
for f in "${el_files[@]}"
do
  echo "Compiling $f"
  emacs --batch -Q -L . \
    -f batch-byte-compile "$f" || exit 1
done

echo "--- checkdoc ---"
for f in "${el_files[@]}"
do
  echo "Checking $f"
  emacs --batch -Q -L . \
    --eval "(checkdoc-file \"$f\")" || exit 1
done

echo "--- ert ---"
test_files=(*-test.el)
if [[ -e "${test_files[0]}" ]]
then
  for f in "${test_files[@]}"
  do
    echo "Running $f"
    emacs --batch -Q -L . \
      -l "$f" \
      -f ert-run-tests-batch-and-exit || exit 1
  done
else
  echo "No *-test.el files found; skipping."
fi

echo "--- done ---"
