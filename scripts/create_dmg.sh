#!/bin/sh
set -eu

APP_PATH="${1:?Usage: create_dmg.sh APP_PATH OUTPUT_DMG [VOLUME_NAME]}"
OUTPUT_DMG="${2:?Usage: create_dmg.sh APP_PATH OUTPUT_DMG [VOLUME_NAME]}"
VOLUME_NAME="${3:-Portside}"

[ -d "$APP_PATH" ] || { echo "Missing app bundle: $APP_PATH" >&2; exit 1; }

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/portside-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$OUTPUT_DMG")"
ditto "$APP_PATH" "$STAGING_DIR/Portside.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG" >/dev/null

echo "Created installer DMG with Applications shortcut: $OUTPUT_DMG"
