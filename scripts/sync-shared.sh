#!/bin/sh
# Copies shared/ into each plugin's lib/. A plugin is loaded from its own folder (often a
# symlink in ~/.config/sekaipop/plugins/), so it can't import ../shared: each carries a
# copy, and this keeps the copies the same.
#
#   scripts/sync-shared.sh          copy
#   scripts/sync-shared.sh --check  exit 1 if a copy differs from shared/ (the tests run this)
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
status=0
for p in "$here"/kumiko-*/; do
    lib="$p/lib"
    if [ "${1:-}" = "--check" ]; then
        if ! diff -r "$here/shared" "$lib" >/dev/null 2>&1; then
            echo "$(basename "$p")/lib differs from shared/: run scripts/sync-shared.sh" >&2
            status=1
        fi
    else
        rm -rf "$lib"
        cp -R "$here/shared" "$lib"
    fi
done
exit $status
