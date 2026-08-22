#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="${PORTSIDE_ENGINE_BUILD_DIR:-$ROOT_DIR/build/engine}"
ENGINE_VERSION="${PORTSIDE_ENGINE_VERSION:?Set PORTSIDE_ENGINE_VERSION}"
BUCKET="${PORTSIDE_PUBLIC_BUCKET:?Set PORTSIDE_PUBLIC_BUCKET}"
SECONDARY_BUCKET="${PORTSIDE_SECONDARY_PUBLIC_BUCKET:?Set PORTSIDE_SECONDARY_PUBLIC_BUCKET}"
PRIMARY_ACCESS_KEY_ID="${PORTSIDE_S3_ACCESS_KEY_ID:?Set PORTSIDE_S3_ACCESS_KEY_ID}"
PRIMARY_SECRET_ACCESS_KEY="${PORTSIDE_S3_SECRET_ACCESS_KEY:?Set PORTSIDE_S3_SECRET_ACCESS_KEY}"
PRIMARY_REGION="${PORTSIDE_S3_REGION:?Set PORTSIDE_S3_REGION}"
PRIMARY_ENDPOINT="${PORTSIDE_S3_ENDPOINT:?Set PORTSIDE_S3_ENDPOINT}"
SECONDARY_ACCESS_KEY_ID="${PORTSIDE_SECONDARY_S3_ACCESS_KEY_ID:?Set PORTSIDE_SECONDARY_S3_ACCESS_KEY_ID}"
SECONDARY_SECRET_ACCESS_KEY="${PORTSIDE_SECONDARY_S3_SECRET_ACCESS_KEY:?Set PORTSIDE_SECONDARY_S3_SECRET_ACCESS_KEY}"
SECONDARY_REGION="${PORTSIDE_SECONDARY_S3_REGION:?Set PORTSIDE_SECONDARY_S3_REGION}"
SECONDARY_ENDPOINT="${PORTSIDE_SECONDARY_S3_ENDPOINT:?Set PORTSIDE_SECONDARY_S3_ENDPOINT}"

command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required for engine publication" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for engine publication" >&2; exit 1; }
archive="$BUILD_DIR/PortsideWineEngine-$ENGINE_VERSION.tar.xz"
metadata="$BUILD_DIR/engine-metadata.json"
checksum="$BUILD_DIR/PortsideWineEngine-$ENGINE_VERSION.sha256"
for file in "$archive" "$metadata" "$checksum"; do
    [ -s "$file" ] || { echo "engine publication file is missing: $file" >&2; exit 1; }
done
jq -e --arg version "$ENGINE_VERSION" '.engineVersion == $version and .artifact.fileName == ("PortsideWineEngine-" + $version + ".tar.xz")' "$metadata" >/dev/null

prefix="runtime/engines/validated/$ENGINE_VERSION"
publish() {
    source_path="$1"
    key="$2"
    content_type="$3"
    bucket="$4"
    access_key_id="$5"
    secret_access_key="$6"
    region="$7"
    endpoint="$8"
    AWS_ACCESS_KEY_ID="$access_key_id" AWS_SECRET_ACCESS_KEY="$secret_access_key" AWS_REGION="$region" AWS_DEFAULT_REGION="$region" AWS_ENDPOINT_URL="$endpoint" \
        aws s3 cp "$source_path" "s3://$bucket/$key" --no-guess-mime-type --content-type "$content_type"
}

publish_bucket() {
    bucket="$1"
    access_key_id="$2"
    secret_access_key="$3"
    region="$4"
    endpoint="$5"
    publish "$archive" "$prefix/$(basename "$archive")" "application/x-xz" "$bucket" "$access_key_id" "$secret_access_key" "$region" "$endpoint" &
    archive_pid=$!
    publish "$checksum" "$prefix/$(basename "$checksum")" "text/plain" "$bucket" "$access_key_id" "$secret_access_key" "$region" "$endpoint" &
    checksum_pid=$!
    publish "$metadata" "$prefix/engine-metadata.json" "application/json" "$bucket" "$access_key_id" "$secret_access_key" "$region" "$endpoint" &
    metadata_pid=$!
    wait "$archive_pid"
    wait "$checksum_pid"
    wait "$metadata_pid"
}

publish_bucket "$BUCKET" "$PRIMARY_ACCESS_KEY_ID" "$PRIMARY_SECRET_ACCESS_KEY" "$PRIMARY_REGION" "$PRIMARY_ENDPOINT"
publish_bucket "$SECONDARY_BUCKET" "$SECONDARY_ACCESS_KEY_ID" "$SECONDARY_SECRET_ACCESS_KEY" "$SECONDARY_REGION" "$SECONDARY_ENDPOINT"

echo "Published validated Portside engine $ENGINE_VERSION to both production buckets."
