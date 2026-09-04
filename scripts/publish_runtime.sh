#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
BUCKET="${PORTSIDE_PUBLIC_BUCKET:?Set PORTSIDE_PUBLIC_BUCKET}"
PRIMARY_ACCESS_KEY_ID="${PORTSIDE_S3_ACCESS_KEY_ID:?Set PORTSIDE_S3_ACCESS_KEY_ID}"
PRIMARY_SECRET_ACCESS_KEY="${PORTSIDE_S3_SECRET_ACCESS_KEY:?Set PORTSIDE_S3_SECRET_ACCESS_KEY}"
PRIMARY_REGION="${PORTSIDE_S3_REGION:?Set PORTSIDE_S3_REGION}"
PRIMARY_ENDPOINT="${PORTSIDE_S3_ENDPOINT:?Set PORTSIDE_S3_ENDPOINT}"
CHANNEL="${PORTSIDE_RUNTIME_CHANNEL:-production}"
[ "$CHANNEL" = production ] || { echo "runtime build publication is production-only" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required for production publication" >&2; exit 1; }

manifest="$BUILD_DIR/runtime-manifest.json"
[ -s "$manifest" ] || { echo "signed runtime-manifest.json is missing" >&2; exit 1; }
for file in "$BUILD_DIR/PortsideWrapper-${PORTSIDE_RUNTIME_VERSION:?}.tar.xz" "$BUILD_DIR/PortsideWineEngine-$PORTSIDE_RUNTIME_VERSION.tar.xz" "$BUILD_DIR/PortsideWinetricks-$PORTSIDE_RUNTIME_VERSION.tar.xz" "$BUILD_DIR/engine-input.json" "$BUILD_DIR/provenance.json" "$BUILD_DIR/sbom.spdx.json"; do
    [ -s "$file" ] || { echo "production artifact is missing: $file" >&2; exit 1; }
done

publish() {
    source_path="$1"
    key="$2"
    content_type="$3"
    env AWS_ACCESS_KEY_ID="$PRIMARY_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$PRIMARY_SECRET_ACCESS_KEY" AWS_REGION="$PRIMARY_REGION" AWS_DEFAULT_REGION="$PRIMARY_REGION" AWS_ENDPOINT_URL="$PRIMARY_ENDPOINT" \
        aws s3 cp "$source_path" "s3://$BUCKET/$key" --no-guess-mime-type --content-type "$content_type"
}

prefix="runtime/$CHANNEL/"
publish "$BUILD_DIR/PortsideWrapper-$PORTSIDE_RUNTIME_VERSION.tar.xz" "${prefix}PortsideWrapper-$PORTSIDE_RUNTIME_VERSION.tar.xz" "application/x-xz"
publish "$BUILD_DIR/PortsideWineEngine-$PORTSIDE_RUNTIME_VERSION.tar.xz" "${prefix}PortsideWineEngine-$PORTSIDE_RUNTIME_VERSION.tar.xz" "application/x-xz"
publish "$BUILD_DIR/PortsideWinetricks-$PORTSIDE_RUNTIME_VERSION.tar.xz" "${prefix}PortsideWinetricks-$PORTSIDE_RUNTIME_VERSION.tar.xz" "application/x-xz"
publish "$BUILD_DIR/runtime-manifest.json" "${prefix}runtime-manifest.json" "application/json"
publish "$BUILD_DIR/engine-input.json" "${prefix}engine-input.json" "application/json"
publish "$BUILD_DIR/provenance.json" "${prefix}provenance.json" "application/json"
publish "$BUILD_DIR/sbom.spdx.json" "${prefix}sbom.spdx.json" "application/json"
echo "Published the signed Portside runtime build to production storage."
