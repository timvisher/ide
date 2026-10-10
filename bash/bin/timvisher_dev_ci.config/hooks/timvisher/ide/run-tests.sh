#!/usr/bin/env bash

hook_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")") || exit 1

ide_root=$(git -C "$hook_dir" rev-parse --show-toplevel) || exit 1
here=$(git rev-parse --show-toplevel) || exit 1

if [[ $here == "$ide_root" ]]
then
    sysext_root=$(realpath "${XDG_CONFIG_HOME:-${HOME}/.config}/timvisher/ide") || exit 1
else
    sysext_root=$here
fi

if ! command -v parallel >/dev/null 2>&1
then
    printf 'GNU parallel not found; install it with `brew install parallel`\n' >&2
    exit 1
fi

results=${TIMVISHER_DEV_CI_RESULTS_FILE:-}

record() {
    if [[ -n $results ]]
    then
        printf '%s\n' "$*" >> "$results"
    fi
}

tmpdir=
cleanup() {
    [[ -z $tmpdir ]] || rm -rf -- "$tmpdir"
}
trap cleanup EXIT
tmpdir=$(mktemp -d) || exit 1

printf 'ide: %s\nsystem-extensions: %s\n' "$ide_root" "$sysext_root"

labels=()
roots=()
rels=()
for spec in "ide:${ide_root}" "system-extensions:${sysext_root}"
do
    name=${spec%%:*}
    root=${spec#*:}
    for t in "$root"/bash/tests/* "$root"/ai/HOME/.agents/skills/*/scripts/tests/*
    do
        [[ -f $t && -x $t ]] || continue
        rel=${t#"$root"/}
        labels+=("${name}/${rel}")
        roots+=("$root")
        rels+=("$rel")
    done
done

parallel -J "$hook_dir/run-tests.parallel" --link --tagstring '{1}' \
    --joblog "$tmpdir/joblog" 'cd -- {2} && ./{3} 2>&1' \
    ::: "${labels[@]}" ::: "${roots[@]}" ::: "${rels[@]}" |
    tee "$tmpdir/log"

failed=()
while read -r seq exitval signal
do
    t=${labels[seq - 1]}
    if (( exitval == 0 && signal == 0 ))
    then
        record "test: $t pass"
        continue
    fi
    failed+=("$t")
    record "test: $t fail"
    if (( exitval == -1 ))
    then
        record "test: $t FAIL: timed out"
    fi
    while IFS= read -r name
    do
        record "test: $t FAIL: $name"
    done < <(awk -F'\t' -v suite="$t" '$1 == suite && $2 ~ /^FAIL: / { sub(/^FAIL: /, "", $2); print $2 }' "$tmpdir/log" |
        sed -e 's/ ([^()]*[:=].*//' | LC_ALL=C sort -u)
done < <(awk -F'\t' 'NR > 1 { print $1, $7, ($8 == "" ? 0 : $8) }' "$tmpdir/joblog" | sort -n)

if (( ${#labels[@]} != $(tail -n +2 "$tmpdir/joblog" | wc -l) ))
then
    printf 'parallel did not run every suite (see the output above)\n' >&2
    exit 1
fi

if (( 0 < ${#failed[@]} ))
then
    printf 'failed: %s\n' "${failed[@]}" >&2
    exit 1
fi
