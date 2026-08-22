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
    changed_files="$changed_files\n$files"
done

[ "$has_push" = true ] || exit 0
changed_files="$(printf '%b\n' "$changed_files" | sed '/^$/d' | sort -u)"

has_path() {
    printf '%s\n' "$changed_files" | grep -Eq "$1"
}

echo "Running targeted pre-push checks..."

if has_path '(^|/)\.github/workflows/'; then
    if command -v actionlint >/dev/null 2>&1; then
        actionlint .github/workflows/*.yml
    else
        echo "actionlint is not installed; GitHub will validate workflow files." >&2
    fi
fi

if has_path '(^|/)scripts/.*\.sh$'; then
    printf '%s\n' "$changed_files" | while IFS= read -r file; do
        case "$file" in
            *.sh) [ -f "$file" ] && sh -n "$file" ;;
        esac
    done
fi

if has_path '\.json$'; then
    command -v jq >/dev/null 2>&1 || {
        echo "jq is required to validate changed JSON files." >&2
        exit 1
    }
    printf '%s\n' "$changed_files" | while IFS= read -r file; do
        case "$file" in
            *.json) [ -f "$file" ] && jq -e empty "$file" >/dev/null ;;
        esac
    done
fi

if has_path '^apps/desktop/'; then
    swift test --package-path apps/desktop
fi

if has_path '^apps/backend/'; then
    [ -d apps/backend/node_modules ] || {
        echo "Backend dependencies are missing. Run: (cd apps/backend && npm ci)" >&2
        exit 1
    }
    (
        cd apps/backend
        npm run prisma:validate
        npm run typecheck
        npm run lint
        npm test
        npm run build
    )
fi

if has_path '^apps/landing/'; then
    command -v bun >/dev/null 2>&1 || {
        echo "bun is required for landing checks." >&2
        exit 1
    }
    [ -d apps/landing/node_modules ] || {
        echo "Landing dependencies are missing. Run: (cd apps/landing && bun install --frozen-lockfile)" >&2
        exit 1
    }
    (cd apps/landing && bun run lint)
fi

if has_path '^(apps/backend/|apps/desktop/|apps/runtime-host/|runtime/|vendor/|upstream/|scripts/build-runtime/|scripts/(build_release|create_dmg|generate_manifest|generate_appcast|notarize_release|package_app|publish_release|publish_runtime|register_runtime_release|sign_release|validate-production-policy|validate_release_bundle)\.sh$)'; then
    ./scripts/validate-production-policy.sh
fi

echo "Targeted pre-push checks passed."
