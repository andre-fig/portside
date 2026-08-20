#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
pattern='https://(raw\.)?github\.com/Sikarugir-App|https://github\.com/Sikarugir-App'
legacy_runtime='WS12WineSikarugir|Template-1\.0|engineArchiveSHA256|templateArchiveSHA256|winetricksSHA256|Contents/MacOS/Sikarugir|WSS-winetricks'

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

if rg -n "$legacy_runtime" "$ROOT_DIR/apps/desktop/Sources" "$ROOT_DIR/apps/backend/src" "$ROOT_DIR/.github/workflows"; then
    echo "legacy upstream runtime artifact or launcher reference found in Release code" >&2
    exit 1
fi

if rg -n -i 'github\.com/Sikarugir-App|raw\.githubusercontent\.com|example\.invalid' "$ROOT_DIR/apps/backend/manifests/runtime-manifest.json" "$ROOT_DIR/docs/runtime-manifest.json"; then
    echo "runtime manifest contains an external or placeholder release source" >&2
    exit 1
fi

if [ -f "$ROOT_DIR/runtime/wrapper-template/Contents/MacOS/PortsideRuntimeHost" ]; then
    echo "compiled runtime host must be produced by the workflow, not committed" >&2
    exit 1
fi

if find "$ROOT_DIR/vendor" -type f \( -name '*.dmg' -o -name '*.tar.xz' -o -name '*.zip' \) -print -quit | grep -q .; then
    echo "compiled runtime archive found under vendor" >&2
    exit 1
fi

for snapshot in sikarugir wrapper engines wine winetricks foss-sources; do
    "$ROOT_DIR/scripts/upstream/validate_snapshot.sh" "$ROOT_DIR/vendor/$snapshot" >/dev/null
done

if find "$ROOT_DIR/vendor" -type d -name .git -print -quit | grep -q .; then
    echo "vendor contains a nested Git repository" >&2
    exit 1
fi

echo "Production source policy passed."
