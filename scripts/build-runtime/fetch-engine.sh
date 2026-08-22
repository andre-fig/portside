#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
RUNTIME_VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
BUCKET="${PORTSIDE_ENGINE_BUCKET:-${PORTSIDE_PUBLIC_BUCKET:?Set PORTSIDE_PUBLIC_BUCKET}}"
ACCESS_KEY_ID="${PORTSIDE_ENGINE_ACCESS_KEY_ID:-${PORTSIDE_S3_ACCESS_KEY_ID:?Set PORTSIDE_S3_ACCESS_KEY_ID}}"
SECRET_ACCESS_KEY="${PORTSIDE_ENGINE_SECRET_ACCESS_KEY:-${PORTSIDE_S3_SECRET_ACCESS_KEY:?Set PORTSIDE_S3_SECRET_ACCESS_KEY}}"
REGION="${PORTSIDE_ENGINE_REGION:-${PORTSIDE_S3_REGION:?Set PORTSIDE_S3_REGION}}"
ENDPOINT="${PORTSIDE_ENGINE_ENDPOINT:-${PORTSIDE_S3_ENDPOINT:?Set PORTSIDE_S3_ENDPOINT}}"

command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required to fetch the validated Portside engine" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to validate the Portside engine" >&2; exit 1; }
case "$BUILD_DIR" in "$ROOT_DIR"/*) ;; *) echo "runtime build directory must be inside the checkout" >&2; exit 1 ;; esac
mkdir -p "$BUILD_DIR/work/engine-input"

engine_info="$("$ROOT_DIR/scripts/build-runtime/resolve-engine.sh")"
engine_version="$(printf '%s' "$engine_info" | jq -r '.engineVersion')"
source_commit="$(printf '%s' "$engine_info" | jq -r '.sourceCommit')"
source_checksum="$(printf '%s' "$engine_info" | jq -r '.sourceSnapshotChecksum')"
archive_name="$(printf '%s' "$engine_info" | jq -r '.archiveName')"
archive_key="$(printf '%s' "$engine_info" | jq -r '.archiveKey')"
archive="$BUILD_DIR/work/engine-input/$archive_name"
metadata="$BUILD_DIR/work/engine-input/engine-metadata.json"

s3_copy() {
    source="$1"
    destination="$2"
    AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION" AWS_ENDPOINT_URL="$ENDPOINT" \
        aws s3 cp "$source" "$destination" --only-show-errors
}

s3_copy "s3://$BUCKET/$archive_key" "$archive" || {
    echo "validated Portside engine is not available for Wine commit $source_commit ($engine_version)" >&2
    echo "expected storage key: $archive_key" >&2
    echo "run Build Portside Engine successfully before assembling this runtime" >&2
    exit 2
}
s3_copy "s3://$BUCKET/$(dirname "$archive_key")/engine-metadata.json" "$metadata"

jq -e \
    --arg engineVersion "$engine_version" \
    --arg sourceCommit "$source_commit" \
    --arg sourceChecksum "$source_checksum" \
    --arg archiveName "$archive_name" \
    --arg archiveKey "$archive_key" \
    '(.schemaVersion == 1) and (.kind == "PortsideRuntimeEngine") and (.engineVersion == $engineVersion) and (.source.commit == $sourceCommit) and (.source.snapshotChecksum == $sourceChecksum) and (.artifact.fileName == $archiveName) and (.artifact.storageKey == $archiveKey) and (.artifact.sha256 | test("^[0-9a-fA-F]{64}$")) and (.artifact.size | numbers) > 0 and (.build.id | strings | length > 0)' \
    "$metadata" >/dev/null

expected_sha256="$(jq -r '.artifact.sha256' "$metadata")"
expected_size="$(jq -r '.artifact.size' "$metadata")"
actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
actual_size="$(wc -c < "$archive" | tr -d '[:space:]')"
[ "$actual_sha256" = "$expected_sha256" ] || { echo "validated Portside engine checksum mismatch" >&2; exit 1; }
[ "$actual_size" = "$expected_size" ] || { echo "validated Portside engine size mismatch" >&2; exit 1; }

runtime_archive="$BUILD_DIR/PortsideWineEngine-$RUNTIME_VERSION.tar.xz"
tar -tJf "$archive" >/dev/null || { echo "validated Portside engine archive is unreadable" >&2; exit 1; }
if tar -tJf "$archive" | grep -Eq '(^/|(^|/)\.\.(\/|$))'; then
    echo "validated Portside engine contains an unsafe archive path" >&2
    exit 1
fi
engine_stage="$BUILD_DIR/work/engine-input/stage"
rm -rf "$engine_stage"
mkdir -p "$engine_stage"
tar -xJf "$archive" -C "$engine_stage"
persistent_root="$engine_stage/PortsideWineEngine-$engine_version"
[ -d "$persistent_root" ] || { echo "validated Portside engine has an unexpected archive root" >&2; exit 1; }
runtime_root="$engine_stage/PortsideWineEngine-$RUNTIME_VERSION"
if [ "$runtime_root" != "$persistent_root" ]; then
    cp -R "$persistent_root" "$runtime_root"
fi
"$ROOT_DIR/scripts/build-runtime/create-archive.sh" "$runtime_archive" "$engine_stage" "PortsideWineEngine-$RUNTIME_VERSION"
cp "$metadata" "$BUILD_DIR/engine-input.json"
runtime_sha256="$(shasum -a 256 "$runtime_archive" | awk '{print $1}')"
printf '%s\n' "$runtime_sha256  PortsideWineEngine-$RUNTIME_VERSION.tar.xz" > "$BUILD_DIR/PortsideWineEngine-$RUNTIME_VERSION.sha256"
echo "Reused validated Portside engine $engine_version for runtime $RUNTIME_VERSION (runtime archive $runtime_sha256)."
