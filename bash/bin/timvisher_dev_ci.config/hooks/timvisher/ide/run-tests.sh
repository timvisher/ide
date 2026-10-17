#!/usr/bin/env bash

hook_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")") || exit 1

ide_root=$(git -C "$hook_dir" rev-parse --show-toplevel) || exit 1
here=$(git rev-parse --show-toplevel) || exit 1

if [[ -e $here/bash/install.bash ]]
then
    core=$here
else
    core=$ide_root
fi

cd "$here" || exit 1
exec "$core/bash/bin/timvisher_tests" "$@"
