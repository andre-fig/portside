#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
VERSION="${PORTSIDE_VERSION:?Set PORTSIDE_VERSION}"
BUCKET="${PORTSIDE_PUBLIC_BUCKET:?Set the approved public object-storage bucket}"
CHANNEL="${PORTSIDE_UPDATE_CHANNEL:-staging}"
case "$CHANNEL" in staging|production) ;; *) echo "Channel must be staging or production" >&2; exit 1;; esac
[ -f "$BUILD_DIR/Portside-${VERSION}-notarized.zip" ] || { echo "Publish only after notarization" >&2; exit 1; }
[ -f "$BUILD_DIR/appcast.xml" ] || { echo "Missing generated appcast.xml" >&2; exit 1; }
[ -f "$BUILD_DIR/checksums.txt" ] || { echo "Missing checksums.txt" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required in the publishing environment" >&2; exit 1; }
aws s3 cp "$BUILD_DIR/Portside-${VERSION}-notarized.zip" "s3://$BUCKET/app/$CHANNEL/Portside-${VERSION}.zip" --no-guess-mime-type --content-type application/zip
aws s3 cp "$BUILD_DIR/appcast.xml" "s3://$BUCKET/app/$CHANNEL/appcast.xml" --content-type application/xml
aws s3 cp "$BUILD_DIR/checksums.txt" "s3://$BUCKET/app/$CHANNEL/checksums.txt" --content-type text/plain
if [ -f "$BUILD_DIR/runtime-manifest.json" ]; then
    aws s3 cp "$BUILD_DIR/runtime-manifest.json" "s3://$BUCKET/runtime/$CHANNEL/runtime-manifest.json" --content-type application/json
fi
echo "Published $VERSION to $CHANNEL; promote the manifest through the authenticated admin API."
