#!/bin/sh
set -eu

ROOT_DIR="${1:?usage: validate_snapshot.sh DIRECTORY}"
[ -d "$ROOT_DIR" ] || { echo "snapshot directory does not exist: $ROOT_DIR" >&2; exit 1; }

if find "$ROOT_DIR" -type d -name .git -print -quit | grep -q .; then
    echo "nested .git directory detected in $ROOT_DIR" >&2
    exit 1
fi

for forbidden in node_modules .build DerivedData coverage; do
    if find "$ROOT_DIR" -type d -name "$forbidden" -print -quit | grep -q .; then
        echo "generated directory detected in $ROOT_DIR: $forbidden" >&2
        exit 1
    fi
done

root_real=$(CDPATH= cd -- "$ROOT_DIR" && pwd -P)
link_list=$(mktemp "${TMPDIR:-/tmp}/portside-links.XXXXXX")
trap 'rm -f "$link_list"' EXIT INT TERM
find "$ROOT_DIR" -type l -print > "$link_list"
while IFS= read -r link; do
    resolved=$(realpath "$link" 2>/dev/null || true)
    case "$resolved" in
        "$root_real"/*) ;;
        *)
            echo "unsafe source symlink detected: $link -> $(readlink "$link")" >&2
            exit 1
            ;;
    esac
done < "$link_list"

echo "validated source snapshot: $ROOT_DIR"
