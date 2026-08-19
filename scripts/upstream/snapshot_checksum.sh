#!/bin/sh
set -eu

ROOT_DIR="${1:?usage: snapshot_checksum.sh DIRECTORY}"
[ -d "$ROOT_DIR" ] || { echo "snapshot directory does not exist: $ROOT_DIR" >&2; exit 1; }

# The digest covers relative paths, file contents and symlink targets while
# deliberately excluding VCS metadata. It is stable across checkout paths.
{
    find "$ROOT_DIR" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
        relative=${file#"$ROOT_DIR"/}
        printf 'file\t%s\t' "$relative"
        shasum -a 256 "$file" | awk '{print $1}'
    done
    find "$ROOT_DIR" -type l -print | LC_ALL=C sort | while IFS= read -r link; do
        relative=${link#"$ROOT_DIR"/}
        printf 'symlink\t%s\t%s\n' "$relative" "$(readlink "$link")"
    done
} | shasum -a 256 | awk '{print $1}'
