#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

changed_files="$(git diff --cached --name-only --diff-filter=ACMRT)"
[ -n "$changed_files" ] || exit 0

echo "Running fast pre-commit checks..."
git diff --cached --check

printf '%s\n' "$changed_files" | while IFS= read -r file; do
    case "$file" in
        *.sh)
            git show ":$file" | sh -n
            ;;
        *.json)
            if command -v jq >/dev/null 2>&1; then
                git show ":$file" | jq -e . >/dev/null
            else
                git show ":$file" | node -e 'JSON.parse(require("node:fs").readFileSync(0, "utf8"))'
            fi
            ;;
        *.py)
            git show ":$file" | python3 -B -c 'import ast, sys; ast.parse(sys.stdin.read())'
            ;;
        .github/workflows/*.yml|.github/workflows/*.yaml)
            command -v actionlint >/dev/null 2>&1 || {
                echo "Install actionlint before committing workflow changes: brew install actionlint" >&2
                exit 1
            }
            git show ":$file" | actionlint -stdin-filename "$file" -
            ;;
    esac
done

echo "Fast pre-commit checks passed."
