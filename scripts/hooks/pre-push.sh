#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

changed_files=""
has_push=false

while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
    [ -n "${local_ref:-}" ] || continue
    [ "$local_ref" = delete ] && continue
    has_push=true

    if [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
        files="$(git ls-tree -r --name-only "$local_sha")"
    else
        git diff --check "$remote_sha..$local_sha"
        files="$(git diff --name-only "$remote_sha..$local_sha")"
    fi
    changed_files="$changed_files
$files"
done

[ "$has_push" = true ] || exit 0
changed_files="$(printf '%s\n' "$changed_files" | sed '/^$/d' | sort -u)"

has_path() {
    printf '%s\n' "$changed_files" | grep -Eq "$1"
}

echo "Running targeted pre-push checks..."

if has_path '(^|/)\.github/workflows/'; then
    if command -v actionlint >/dev/null 2>&1; then
        actionlint .github/workflows/*.yml
    else
        echo "Install actionlint before pushing workflow changes: brew install actionlint" >&2
        exit 1
    fi
fi

if has_path '(^|/)scripts/.*\.(sh|py)$'; then
    printf '%s\n' "$changed_files" | while IFS= read -r file; do
        [ -f "$file" ] || continue
        case "$file" in
            *.sh) sh -n "$file" ;;
            *.py) python3 -B -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' "$file" ;;
        esac
    done
fi

if has_path '\.json$'; then
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$changed_files" | while IFS= read -r file; do
            [ -f "$file" ] || continue
            case "$file" in
                *.json) jq -e . "$file" >/dev/null ;;
            esac
        done
    else
        printf '%s\n' "$changed_files" | while IFS= read -r file; do
            [ -f "$file" ] || continue
            case "$file" in
                *.json)
                    node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' "$file"
                    ;;
            esac
        done
    fi
fi

if has_path '^(apps/desktop/|apps/runtime-host/|runtime/wrapper-template/|scripts/build-runtime/build-wrapper\.sh$)'; then
    swift test --package-path apps/desktop
    swift build --package-path apps/desktop
fi

if has_path '^(apps/runtime-host/|apps/desktop/|runtime/wrapper-template/|scripts/build-runtime/build-wrapper\.sh$)'; then
    swift test --package-path apps/runtime-host
    swift build --package-path apps/runtime-host
fi

if has_path '^(\.github/workflows/|scripts/)'; then
    python3 -B -m unittest discover -s scripts/tests -v
fi

if has_path '^apps/backend/'; then
    [ -d apps/backend/node_modules ] || {
        echo "Backend dependencies are missing. Run: (cd apps/backend && npm ci)" >&2
        exit 1
    }
    (
        cd apps/backend
        if [ -n "${DATABASE_URL:-}" ]; then
            npm run prisma:validate
        else
            DATABASE_URL='postgresql://postgres:postgres@localhost:5432/portside' npm run prisma:validate
        fi
        npm run typecheck
        npm run lint
        npm test
        npm run build
    )
fi

if has_path '^apps/landing/'; then
    [ -d apps/landing/node_modules ] || {
        echo "Landing dependencies are missing. Run: (cd apps/landing && bun install --frozen-lockfile)" >&2
        exit 1
    }
    (
        cd apps/landing
        if command -v bun >/dev/null 2>&1; then
            bun run lint
            bun run typecheck
            bun run build
        else
            npm run lint
            npm run typecheck
            npm run build
        fi
    )
fi

if has_path '^(\.github/workflows/|apps/backend/|apps/desktop/|apps/runtime-host/|runtime/|vendor/|upstream/|scripts/)'; then
    ./scripts/validate-production-policy.sh
fi

echo "Targeted pre-push checks passed."
