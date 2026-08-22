#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_ENGINE_BUILD_DIR:-${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/engine}}"
PORTSIDE_COMMIT="${PORTSIDE_COMMIT:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
ENGINE_INFO="$("$ROOT_DIR/scripts/build-runtime/resolve-engine.sh")"
ENGINE_VERSION="$(printf '%s' "$ENGINE_INFO" | jq -r '.engineVersion')"
SOURCE_COMMIT="$(printf '%s' "$ENGINE_INFO" | jq -r '.sourceCommit')"
SOURCE_CHECKSUM="$(printf '%s' "$ENGINE_INFO" | jq -r '.sourceSnapshotChecksum')"
ARCHIVE_NAME="$(printf '%s' "$ENGINE_INFO" | jq -r '.archiveName')"
ARCHIVE_KEY="$(printf '%s' "$ENGINE_INFO" | jq -r '.archiveKey')"

case "$BUILD_DIR" in "$ROOT_DIR"/*) ;; *) echo "engine build directory must be inside the checkout" >&2; exit 1 ;; esac
mkdir -p "$BUILD_DIR"
rm -f "$BUILD_DIR/engine-metadata.json" "$BUILD_DIR/engine-provenance.json"

PORTSIDE_RUNTIME_VERSION="$ENGINE_VERSION" \
PORTSIDE_RUNTIME_BUILD_DIR="$BUILD_DIR" \
    "$ROOT_DIR/scripts/build-runtime/build-wine-engine.sh"

archive="$BUILD_DIR/$ARCHIVE_NAME"
[ -s "$archive" ] || { echo "Wine build did not produce $archive" >&2; exit 1; }
archive_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
archive_size="$(wc -c < "$archive" | tr -d '[:space:]')"
build_id="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
macos_version="$(sw_vers -productVersion 2>/dev/null || uname -s)"
xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ';' || true)"
clang_version="$(clang --version | head -n 1)"

jq -n \
    --arg engineVersion "$ENGINE_VERSION" \
    --arg sourceCommit "$SOURCE_COMMIT" \
    --arg sourceSnapshotChecksum "$SOURCE_CHECKSUM" \
    --arg archiveName "$ARCHIVE_NAME" \
    --arg archiveKey "$ARCHIVE_KEY" \
    --arg archiveSHA256 "$archive_sha256" \
    --arg archiveSize "$archive_size" \
    --arg buildId "$build_id" \
    --arg portsideCommit "$PORTSIDE_COMMIT" \
    --arg macOS "$macos_version" \
    --arg xcode "$xcode_version" \
    --arg clang "$clang_version" \
    '{schemaVersion: 1, kind: "PortsideRuntimeEngine", engineVersion: $engineVersion, source: {repository: "https://github.com/Sikarugir-App/wine", commit: $sourceCommit, snapshotChecksum: $sourceSnapshotChecksum}, artifact: {fileName: $archiveName, storageKey: $archiveKey, sha256: $archiveSHA256, size: ($archiveSize|tonumber)}, build: {id: $buildId, portsideCommit: $portsideCommit, macOS: $macOS, xcode: $xcode, clang: $clang}}' \
    > "$BUILD_DIR/engine-metadata.json"

jq -n \
    --arg engineVersion "$ENGINE_VERSION" \
    --arg sourceCommit "$SOURCE_COMMIT" \
    --arg sourceSnapshotChecksum "$SOURCE_CHECKSUM" \
    --arg archiveName "$ARCHIVE_NAME" \
    --arg archiveSHA256 "$archive_sha256" \
    --arg archiveSize "$archive_size" \
    --arg buildId "$build_id" \
    --arg portsideCommit "$PORTSIDE_COMMIT" \
    '{schemaVersion: 1, kind: "PortsideRuntimeEngine", sourcePolicy: "checked-in vendor/wine only; no compiled upstream input", engineVersion: $engineVersion, buildId: $buildId, portsideCommit: $portsideCommit, source: {repository: "https://github.com/Sikarugir-App/wine", commit: $sourceCommit, snapshotChecksum: $sourceSnapshotChecksum}, artifact: {fileName: $archiveName, sha256: $archiveSHA256, size: ($archiveSize|tonumber)}}' \
    > "$BUILD_DIR/engine-provenance.json"

printf '%s\n' "$archive_sha256  $ARCHIVE_NAME" > "$BUILD_DIR/$ARCHIVE_NAME.sha256"
echo "Built persistent Portside engine $ENGINE_VERSION from vendor/wine $SOURCE_COMMIT."
