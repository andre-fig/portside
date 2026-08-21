#!/bin/sh
set -eu

VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
SOURCE_CHANNEL="${PORTSIDE_RUNTIME_SOURCE_CHANNEL:-staging}"
TARGET_CHANNEL="${PORTSIDE_RUNTIME_TARGET_CHANNEL:-production}"
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

case "$SOURCE_CHANNEL:$TARGET_CHANNEL" in
    staging:production) ;;
    *) echo "Runtime promotion is restricted to staging -> production" >&2; exit 1;;
esac
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required in the publishing environment" >&2; exit 1; }

copy_bucket() {
    bucket="$1"
    access_key_id="$2"
    secret_access_key="$3"
    region="$4"
    endpoint="$5"
    for runtime_file in \
        "PortsideWrapper-${VERSION}.tar.xz" \
        "PortsideWineEngine-${VERSION}.tar.xz" \
        "PortsideWinetricks-${VERSION}.tar.xz" \
        provenance.json \
        sbom.spdx.json; do
        content_type="application/x-xz"
        case "$runtime_file" in
            *.json) content_type="application/json" ;;
        esac
        env AWS_ACCESS_KEY_ID="$access_key_id" AWS_SECRET_ACCESS_KEY="$secret_access_key" AWS_REGION="$region" AWS_DEFAULT_REGION="$region" AWS_ENDPOINT_URL="$endpoint" \
            aws s3 cp \
            "s3://$bucket/runtime/$SOURCE_CHANNEL/$runtime_file" \
            "s3://$bucket/runtime/$TARGET_CHANNEL/$runtime_file" \
            --no-guess-mime-type --content-type "$content_type"
    done
}

copy_bucket "$BUCKET" "$PRIMARY_ACCESS_KEY_ID" "$PRIMARY_SECRET_ACCESS_KEY" "$PRIMARY_REGION" "$PRIMARY_ENDPOINT" &
primary_pid=$!
copy_bucket "$SECONDARY_BUCKET" "$SECONDARY_ACCESS_KEY_ID" "$SECONDARY_SECRET_ACCESS_KEY" "$SECONDARY_REGION" "$SECONDARY_ENDPOINT" &
secondary_pid=$!
wait "$primary_pid"
wait "$secondary_pid"
echo "Promoted runtime $VERSION from $SOURCE_CHANNEL to $TARGET_CHANNEL in both Portside buckets."
