#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
VERSION="${PORTSIDE_VERSION:?Set PORTSIDE_VERSION}"
BUCKET="${PORTSIDE_PUBLIC_BUCKET:?Set the approved public object-storage bucket}"
SECONDARY_BUCKET="${PORTSIDE_SECONDARY_PUBLIC_BUCKET:?Set the approved secondary object-storage bucket}"
CHANNEL="${PORTSIDE_UPDATE_CHANNEL:-staging}"
case "$CHANNEL" in staging|production) ;; *) echo "Channel must be staging or production" >&2; exit 1;; esac
[ "$CHANNEL" != production ] || [ "${PORTSIDE_CONFIRM_PRODUCTION:-}" = YES ] || { echo "Production publication requires PORTSIDE_CONFIRM_PRODUCTION=YES" >&2; exit 1; }
[ -f "$BUILD_DIR/Portside-${VERSION}-notarized.zip" ] || { echo "Publish only after notarization" >&2; exit 1; }
[ -f "$BUILD_DIR/appcast.xml" ] || { echo "Missing generated appcast.xml" >&2; exit 1; }
[ -f "$BUILD_DIR/checksums.txt" ] || { echo "Missing checksums.txt" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required in the publishing environment" >&2; exit 1; }

publish_object() {
    source_path="$1"
    primary_key="$2"
    content_type="$3"
    aws s3 cp "$source_path" "s3://$BUCKET/$primary_key" --no-guess-mime-type --content-type "$content_type"
    aws s3 cp "$source_path" "s3://$SECONDARY_BUCKET/$primary_key" --no-guess-mime-type --content-type "$content_type"
}

publish_object "$BUILD_DIR/Portside-${VERSION}-notarized.zip" "app/$CHANNEL/Portside-${VERSION}.zip" "application/zip"
publish_object "$BUILD_DIR/appcast.xml" "app/$CHANNEL/appcast.xml" "application/xml"
publish_object "$BUILD_DIR/checksums.txt" "app/$CHANNEL/checksums.txt" "text/plain"
if [ -f "$BUILD_DIR/runtime-manifest.json" ]; then
    publish_object "$BUILD_DIR/runtime-manifest.json" "runtime/$CHANNEL/runtime-manifest.json" "application/json"
fi
echo "Published $VERSION to primary and secondary storage in $CHANNEL. Explicit release promotion remains required."
