#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
VERSION="${PORTSIDE_VERSION:?Set PORTSIDE_VERSION}"
RUNTIME_VERSION="${PORTSIDE_RUNTIME_VERSION:-$VERSION}"
BUCKET="${PORTSIDE_PUBLIC_BUCKET:?Set the approved public object-storage bucket}"
SECONDARY_BUCKET="${PORTSIDE_SECONDARY_PUBLIC_BUCKET:?Set the approved secondary object-storage bucket}"
PRIMARY_ACCESS_KEY_ID="${PORTSIDE_S3_ACCESS_KEY_ID:?Set PORTSIDE_S3_ACCESS_KEY_ID}"
PRIMARY_SECRET_ACCESS_KEY="${PORTSIDE_S3_SECRET_ACCESS_KEY:?Set PORTSIDE_S3_SECRET_ACCESS_KEY}"
PRIMARY_REGION="${PORTSIDE_S3_REGION:?Set PORTSIDE_S3_REGION}"
PRIMARY_ENDPOINT="${PORTSIDE_S3_ENDPOINT:?Set PORTSIDE_S3_ENDPOINT}"
SECONDARY_ACCESS_KEY_ID="${PORTSIDE_SECONDARY_S3_ACCESS_KEY_ID:?Set PORTSIDE_SECONDARY_S3_ACCESS_KEY_ID}"
SECONDARY_SECRET_ACCESS_KEY="${PORTSIDE_SECONDARY_S3_SECRET_ACCESS_KEY:?Set PORTSIDE_SECONDARY_S3_SECRET_ACCESS_KEY}"
SECONDARY_REGION="${PORTSIDE_SECONDARY_S3_REGION:?Set PORTSIDE_SECONDARY_S3_REGION}"
SECONDARY_ENDPOINT="${PORTSIDE_SECONDARY_S3_ENDPOINT:?Set PORTSIDE_SECONDARY_S3_ENDPOINT}"
CHANNEL="${PORTSIDE_UPDATE_CHANNEL:-production}"
SKIP_RUNTIME_ARCHIVES="${PORTSIDE_SKIP_RUNTIME_ARCHIVES:-0}"
[ "$CHANNEL" = production ] || { echo "Channel must be production" >&2; exit 1; }
[ "$CHANNEL" != production ] || [ "${PORTSIDE_CONFIRM_PRODUCTION:-}" = YES ] || { echo "Production publication requires PORTSIDE_CONFIRM_PRODUCTION=YES" >&2; exit 1; }
[ "$SKIP_RUNTIME_ARCHIVES" = 0 ] || [ "$SKIP_RUNTIME_ARCHIVES" = 1 ] || { echo "PORTSIDE_SKIP_RUNTIME_ARCHIVES must be 0 or 1" >&2; exit 1; }
[ -f "$BUILD_DIR/Portside-${VERSION}-notarized.zip" ] || { echo "Publish only after notarization" >&2; exit 1; }
[ -f "$BUILD_DIR/appcast.xml" ] || { echo "Missing generated appcast.xml" >&2; exit 1; }
[ -f "$BUILD_DIR/checksums.txt" ] || { echo "Missing checksums.txt" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required in the publishing environment" >&2; exit 1; }

publish_object() {
    source_path="$1"
    primary_key="$2"
    content_type="$3"
    publish_to_bucket() {
        bucket="$1"
        access_key_id="$2"
        secret_access_key="$3"
        region="$4"
        endpoint="$5"
        env AWS_ACCESS_KEY_ID="$access_key_id" AWS_SECRET_ACCESS_KEY="$secret_access_key" AWS_REGION="$region" AWS_DEFAULT_REGION="$region" AWS_ENDPOINT_URL="$endpoint" \
            aws s3 cp "$source_path" "s3://$bucket/$primary_key" --no-guess-mime-type --content-type "$content_type"
    }
    publish_to_bucket "$BUCKET" "$PRIMARY_ACCESS_KEY_ID" "$PRIMARY_SECRET_ACCESS_KEY" "$PRIMARY_REGION" "$PRIMARY_ENDPOINT" &
    primary_pid=$!
    publish_to_bucket "$SECONDARY_BUCKET" "$SECONDARY_ACCESS_KEY_ID" "$SECONDARY_SECRET_ACCESS_KEY" "$SECONDARY_REGION" "$SECONDARY_ENDPOINT" &
    secondary_pid=$!
    wait "$primary_pid"
    wait "$secondary_pid"
}

publish_object "$BUILD_DIR/Portside-${VERSION}-notarized.zip" "app/$CHANNEL/Portside-${VERSION}.zip" "application/zip"
publish_object "$BUILD_DIR/Portside-${VERSION}.dmg" "app/$CHANNEL/Portside-${VERSION}.dmg" "application/x-apple-diskimage"
publish_object "$BUILD_DIR/appcast.xml" "app/$CHANNEL/appcast.xml" "application/xml"
publish_object "$BUILD_DIR/checksums.txt" "app/$CHANNEL/checksums.txt" "text/plain"
if [ "$SKIP_RUNTIME_ARCHIVES" = 1 ]; then
    runtime_files="runtime-manifest.json provenance.json sbom.spdx.json"
else
    runtime_files="PortsideWrapper-${RUNTIME_VERSION}.tar.xz PortsideWineEngine-${RUNTIME_VERSION}.tar.xz PortsideWinetricks-${RUNTIME_VERSION}.tar.xz runtime-manifest.json provenance.json sbom.spdx.json"
fi
for runtime_file in $runtime_files; do
    [ -f "$BUILD_DIR/$runtime_file" ] || { echo "Missing runtime release file: $runtime_file" >&2; exit 1; }
    case "$runtime_file" in
        *.json) content_type="application/json" ;;
        *) content_type="application/x-xz" ;;
    esac
    publish_object "$BUILD_DIR/$runtime_file" "runtime/$CHANNEL/$runtime_file" "$content_type"
done
echo "Published production release $VERSION to primary and secondary storage."
