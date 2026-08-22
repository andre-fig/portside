#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
LOCK_FILE="$ROOT_DIR/upstream/lock.json"

command -v jq >/dev/null 2>&1 || { echo "jq is required to resolve the Portside engine" >&2; exit 1; }
[ -s "$LOCK_FILE" ] || { echo "upstream/lock.json is missing" >&2; exit 1; }

wine_commit="$(jq -r '.repositories[] | select(.name == "wine") | .commit' "$LOCK_FILE")"
wine_checksum="$(jq -r '.repositories[] | select(.name == "wine") | .snapshotChecksum' "$LOCK_FILE")"
wine_version="$(tr -d '[:space:]' < "$ROOT_DIR/vendor/wine/VERSION")"

case "$wine_commit" in
    ''|null|*[!0-9a-fA-F]*) echo "the pinned Wine commit is invalid" >&2; exit 1 ;;
esac
case "$wine_checksum" in
    ''|null|*[!0-9a-fA-F]*) echo "the pinned Wine snapshot checksum is invalid" >&2; exit 1 ;;
esac
case "$wine_version" in
    ''|*[!A-Za-z0-9._-]*) echo "the vendored Wine version is invalid" >&2; exit 1 ;;
esac

short_commit="$(printf '%s' "$wine_commit" | cut -c 1-12)"
engine_version="wine-${wine_version}-${short_commit}"
archive_name="PortsideWineEngine-${engine_version}.tar.xz"
archive_key="runtime/engines/validated/${engine_version}/${archive_name}"

jq -n \
    --arg engineVersion "$engine_version" \
    --arg sourceCommit "$wine_commit" \
    --arg sourceSnapshotChecksum "$wine_checksum" \
    --arg archiveName "$archive_name" \
    --arg archiveKey "$archive_key" \
    '{schemaVersion: 1, engineVersion: $engineVersion, sourceCommit: $sourceCommit, sourceSnapshotChecksum: $sourceSnapshotChecksum, archiveName: $archiveName, archiveKey: $archiveKey}'
