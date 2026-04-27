#!/usr/bin/env bash
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FE_BIN="${FE_BIN:-fe}"

result=0

printf 'Using FE_BIN=%s\n' "$FE_BIN"

for dir in "$root"/examples/*; do
    [ -f "$dir/foundry.toml" ] || continue

    name="${dir#"$root"/}"
    printf '\n[%s]\n' "$name"

    if (cd "$dir" && forge test -vv "$@"); then
        printf '[%s passed]\n' "$name"
    else
        code=$?
        printf '[%s failed with exit code %s]\n' "$name" "$code"
        result=1
    fi
done

exit "$result"
