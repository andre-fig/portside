#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

changed_files="$(git diff --cached --name-only --diff-filter=ACMRT)"
[ -n "$changed_files" ] || exit 0

echo "Running fast pre-commit checks..."
git diff --cached --check

printf '%s\n' "$changed_files" | while IFS= read -r file; do
    [ -f "$file" ] || continue
    case "$file" in
        *.sh)
            sh -n "$file"
            ;;
        *.json)
            command -v jq >/dev/null 2>&1 || {
                echo "jq is required to validate staged JSON: $file" >&2
                exit 1
            }
            jq -e empty "$file" >/dev/null
            ;;
    esac
done

if printf '%s\n' "$changed_files" | grep -Eq '^\.github/workflows/'; then
    if command -v actionlint >/dev/null 2>&1; then
        actionlint .github/workflows/*.yml
    else
        echo "actionlint is not installed; GitHub will validate workflow files." >&2
    fi
fi

echo "Fast pre-commit checks passed."
