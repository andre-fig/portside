#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
BUCKET="${PORTSIDE_PUBLIC_BUCKET:?Set PORTSIDE_PUBLIC_BUCKET}"
SECONDARY_BUCKET="${PORTSIDE_SECONDARY_PUBLIC_BUCKET:?Set PORTSIDE_SECONDARY_PUBLIC_BUCKET}"
CHANNEL="${PORTSIDE_RUNTIME_CHANNEL:-staging}"
[ "$CHANNEL" = staging ] || { echo "runtime build publication is staging-only" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required for staging publication" >&2; exit 1; }

manifest="$BUILD_DIR/runtime-manifest.json"
[ -s "$manifest" ] || { echo "signed runtime-manifest.json is missing" >&2; exit 1; }
for file in "$BUILD_DIR/PortsideWrapper-${PORTSIDE_RUNTIME_VERSION:?}.tar.xz" "$BUILD_DIR/PortsideWineEngine-$PORTSIDE_RUNTIME_VERSION.tar.xz" "$BUILD_DIR/PortsideWinetricks-$PORTSIDE_RUNTIME_VERSION.tar.xz" "$BUILD_DIR/provenance.json" "$BUILD_DIR/sbom.spdx.json"; do
    [ -s "$file" ] || { echo "staging artifact is missing: $file" >&2; exit 1; }
done

publish() {
    source_path="$1"
    key="$2"
    content_type="$3"
    aws s3 cp "$source_path" "s3://$BUCKET/$key" --no-guess-mime-type --content-type "$content_type"
    aws s3 cp "$source_path" "s3://$SECONDARY_BUCKET/$key" --no-guess-mime-type --content-type "$content_type"
}

prefix="runtime/$CHANNEL/"
publish "$BUILD_DIR/PortsideWrapper-$PORTSIDE_RUNTIME_VERSION.tar.xz" "${prefix}PortsideWrapper-$PORTSIDE_RUNTIME_VERSION.tar.xz" "application/x-xz"
publish "$BUILD_DIR/PortsideWineEngine-$PORTSIDE_RUNTIME_VERSION.tar.xz" "${prefix}PortsideWineEngine-$PORTSIDE_RUNTIME_VERSION.tar.xz" "application/x-xz"
publish "$BUILD_DIR/PortsideWinetricks-$PORTSIDE_RUNTIME_VERSION.tar.xz" "${prefix}PortsideWinetricks-$PORTSIDE_RUNTIME_VERSION.tar.xz" "application/x-xz"
publish "$BUILD_DIR/runtime-manifest.json" "${prefix}runtime-manifest.json" "application/json"
publish "$BUILD_DIR/provenance.json" "${prefix}provenance.json" "application/json"
publish "$BUILD_DIR/sbom.spdx.json" "${prefix}sbom.spdx.json" "application/json"
echo "Published the signed Portside runtime build to staging storage."
