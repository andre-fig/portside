#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
pattern='https://(raw\.)?github\.com/Sikarugir-App|https://github\.com/Sikarugir-App'

# Upstream URLs are allowed only in provenance/lock documentation. They must
# not appear in release code, runtime manifests, or production workflows.
for path in \
    "$ROOT_DIR/apps/desktop/Sources" \
    "$ROOT_DIR/apps/backend/src" \
    "$ROOT_DIR/.github/workflows" \
    "$ROOT_DIR/docs/runtime-manifest.json"; do
    if rg -n "$pattern" "$path"; then
        echo "direct upstream release dependency found in $path" >&2
        exit 1
    fi
done

for snapshot in sikarugir wrapper engines wine winetricks foss-sources; do
    "$ROOT_DIR/scripts/upstream/validate_snapshot.sh" "$ROOT_DIR/vendor/$snapshot" >/dev/null
done

if find "$ROOT_DIR/vendor" -type d -name .git -print -quit | grep -q .; then
    echo "vendor contains a nested Git repository" >&2
    exit 1
fi

echo "Production source policy passed."
