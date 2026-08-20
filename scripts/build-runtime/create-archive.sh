#!/bin/sh
set -eu

ARCHIVE="${1:?usage: create-archive.sh ARCHIVE ROOT ITEM}"
ROOT="${2:?usage: create-archive.sh ARCHIVE ROOT ITEM}"
ITEM="${3:?usage: create-archive.sh ARCHIVE ROOT ITEM}"

[ -d "$ROOT/$ITEM" ] || { echo "archive item does not exist: $ROOT/$ITEM" >&2; exit 1; }
case "$ROOT/$ITEM" in "$ROOT"/*) ;; *) echo "archive item escapes root" >&2; exit 1 ;; esac

# BSD tar on macOS has no portable --mtime/--sort equivalent. Normalize the
# staged tree before archiving, then normalize ownership and macOS metadata in
# the archive itself. The staged tree is disposable build output.
find "$ROOT/$ITEM" -exec touch -h -t 197001010000 {} +
tar -cJf "$ARCHIVE" \
    --uid 0 --gid 0 --uname root --gname wheel \
    --no-xattrs --no-acls --no-mac-metadata \
    -C "$ROOT" "$ITEM"
