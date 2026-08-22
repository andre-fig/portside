#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
COMPONENT="${1:?usage: changed-components.sh engine|assembly BASE HEAD}"
BASE="${2:?usage: changed-components.sh engine|assembly BASE HEAD}"
HEAD="${3:?usage: changed-components.sh engine|assembly BASE HEAD}"

case "$COMPONENT" in
    engine|assembly) ;;
    *) echo "unknown runtime component: $COMPONENT" >&2; exit 2 ;;
esac

if [ "$BASE" = "0000000000000000000000000000000000000000" ] || ! git -C "$ROOT_DIR" cat-file -e "$BASE^{commit}" 2>/dev/null; then
    changed_files="$(git -C "$ROOT_DIR" diff-tree --root --no-commit-id --name-only -r "$HEAD")"
else
    changed_files="$(git -C "$ROOT_DIR" diff --name-only "$BASE" "$HEAD")"
fi

engine_changed=0
assembly_changed=0
while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
        vendor/wine/*|upstream/dependencies.json|upstream/patches/*|scripts/build-runtime/build-wine-engine.sh|scripts/build-runtime/build-engine.sh|scripts/publish_engine.sh|.github/workflows/build-engine.yml)
            engine_changed=1 ;;
        vendor/winetricks/*|apps/runtime-host/*|runtime/wrapper-template/*|scripts/build-runtime/build.sh|scripts/build-runtime/build-wrapper.sh|scripts/build-runtime/build-winetricks.sh|scripts/build-runtime/fetch-engine.sh|scripts/build-runtime/resolve-engine.sh|scripts/build-runtime/changed-components.sh|scripts/build-runtime/validate-clean-layout.sh|scripts/build-runtime/validate-manifest.sh|scripts/generate_manifest.sh|scripts/publish_runtime.sh|.github/workflows/build-runtime.yml)
            assembly_changed=1 ;;
        scripts/build-runtime/create-archive.sh|scripts/build-runtime/source-audit.sh)
            engine_changed=1
            assembly_changed=1 ;;
        upstream/lock.json)
            if [ "$BASE" = "0000000000000000000000000000000000000000" ]; then
                engine_changed=1
                assembly_changed=1
            else
                old_wine="$(git -C "$ROOT_DIR" show "$BASE:upstream/lock.json" 2>/dev/null | jq -r '.repositories[] | select(.name == "wine") | [.commit, .snapshotChecksum] | join("|")' 2>/dev/null || true)"
                new_wine="$(git -C "$ROOT_DIR" show "$HEAD:upstream/lock.json" 2>/dev/null | jq -r '.repositories[] | select(.name == "wine") | [.commit, .snapshotChecksum] | join("|")' 2>/dev/null || true)"
                old_winetricks="$(git -C "$ROOT_DIR" show "$BASE:upstream/lock.json" 2>/dev/null | jq -r '.repositories[] | select(.name == "winetricks") | [.commit, .snapshotChecksum] | join("|")' 2>/dev/null || true)"
                new_winetricks="$(git -C "$ROOT_DIR" show "$HEAD:upstream/lock.json" 2>/dev/null | jq -r '.repositories[] | select(.name == "winetricks") | [.commit, .snapshotChecksum] | join("|")' 2>/dev/null || true)"
                [ "$old_wine" = "$new_wine" ] || engine_changed=1
                [ "$old_winetricks" = "$new_winetricks" ] || assembly_changed=1
            fi ;;
    esac
done <<EOF
$changed_files
EOF

case "$COMPONENT" in
    engine) [ "$engine_changed" -eq 1 ] ;;
    assembly) [ "$assembly_changed" -eq 1 ] ;;
esac
