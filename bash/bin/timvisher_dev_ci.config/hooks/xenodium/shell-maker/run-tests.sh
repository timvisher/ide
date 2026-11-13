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

# Four tests create a real PNG and assert markdown-overlays matches it, but
# markdown-overlays checks image-supported-file-p first and this Emacs is
# built without image support (no PNG in system-configuration-features), so
# they cannot pass here. agent-shell guards its equivalents with skip-unless;
# shell-maker does not. Skip exactly those four when the build cannot load an
# image, and run them when it can -- rather than excluding by name pattern,
# which would also drop the 17 image-parsing tests that pass fine.
images_ok=true
if ! emacs --batch -Q --eval '(kill-emacs (if (image-type-available-p (quote png)) 0 1))' 2>/dev/null
then
  images_ok=false
  echo "No image support in this Emacs; 4 image-loading tests will be skipped"
fi

# All four live in markdown-overlays-images-tests.el, and ERT's `member`
# selector requires the tests it names to exist -- each file gets its own
# Emacs, so the selector only applies to the file that defines them.
image_skips='(not (member markdown-overlays-image-file-paths-test-absolute
                          markdown-overlays-image-file-paths-test-file-uri
                          markdown-overlays-image-file-paths-test-with-whitespace
                          markdown-overlays-images-test-put-returns-image-file-paths))'

# shell-maker keeps its ERT files in tests/ and names them *-tests.el; the
# root *-test.el glob matched nothing, so this step printed "skipping" and
# exited 0 while testing none of its behaviour.
test_files=(tests/*-tests.el)
if [[ -e "${test_files[0]}" ]]
then
  for f in "${test_files[@]}"
  do
    echo "Running $f"
    selector=t
    if [[ $images_ok == false && $f == *markdown-overlays-images-tests.el ]]
    then
      selector=$image_skips
    fi

    emacs --batch -Q -L . -L tests \
      -l "$f" \
      --eval "(ert-run-tests-batch-and-exit '${selector})" || exit 1
  done
else
  echo "No tests/*-tests.el files found; skipping."
fi

echo "--- done ---"
