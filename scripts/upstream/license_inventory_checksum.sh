#!/bin/sh
set -eu

ROOT_DIR="${1:?usage: license_inventory_checksum.sh DIRECTORY}"
[ -d "$ROOT_DIR" ] || { echo "snapshot directory does not exist: $ROOT_DIR" >&2; exit 1; }

# This is intentionally separate from the full snapshot checksum. It makes a
# license/notice change visible to the synchronization workflow without
# treating ordinary source changes as legal changes.
{
    find "$ROOT_DIR" -type f \( \
        -iname 'license' -o -iname 'license.*' -o -iname 'copying' -o \
        -iname 'copying.*' -o -iname 'notice' -o -iname 'notice.*' \
    \) -print | LC_ALL=C sort | while IFS= read -r file; do
        relative=${file#"$ROOT_DIR"/}
        printf 'file\t%s\t' "$relative"
        shasum -a 256 "$file" | awk '{print $1}'
    done
} | shasum -a 256 | awk '{print $1}'
