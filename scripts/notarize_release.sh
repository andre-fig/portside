#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
VERSION="${PORTSIDE_VERSION:?Set PORTSIDE_VERSION}"
ZIP="$BUILD_DIR/Portside-${VERSION}.zip"
[ -f "$ZIP" ] || { echo "Missing signed archive $ZIP" >&2; exit 1; }

NOTARY_KEY_ID="${PORTSIDE_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${PORTSIDE_NOTARY_ISSUER_ID:-}"
NOTARY_KEY_PATH="${PORTSIDE_NOTARY_KEY_PATH:-}"
NOTARY_PROFILE="${PORTSIDE_NOTARY_PROFILE:-}"

if [ -n "$NOTARY_KEY_ID$NOTARY_ISSUER_ID$NOTARY_KEY_PATH" ]; then
  [ -n "$NOTARY_KEY_ID" ] || { echo "Missing PORTSIDE_NOTARY_KEY_ID" >&2; exit 1; }
  [ -n "$NOTARY_ISSUER_ID" ] || { echo "Missing PORTSIDE_NOTARY_ISSUER_ID" >&2; exit 1; }
  [ -n "$NOTARY_KEY_PATH" ] || { echo "Missing PORTSIDE_NOTARY_KEY_PATH" >&2; exit 1; }
  [ -s "$NOTARY_KEY_PATH" ] || { echo "Missing or empty App Store Connect private key: $NOTARY_KEY_PATH" >&2; exit 1; }

  submit_for_notarization() {
    xcrun notarytool submit "$1" \
      --issuer "$NOTARY_ISSUER_ID" \
      --key-id "$NOTARY_KEY_ID" \
      --key "$NOTARY_KEY_PATH" \
      --wait
  }
elif [ -n "$NOTARY_PROFILE" ]; then
  submit_for_notarization() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  }
else
  echo "Set Team API Key credentials (PORTSIDE_NOTARY_KEY_ID, PORTSIDE_NOTARY_ISSUER_ID and PORTSIDE_NOTARY_KEY_PATH) or PORTSIDE_NOTARY_PROFILE" >&2
  exit 1
fi

submit_for_notarization "$ZIP"
xcrun stapler staple "$BUILD_DIR/Portside.app"
xcrun stapler validate "$BUILD_DIR/Portside.app"
codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/Portside.app"
spctl --assess --type execute --verbose=4 "$BUILD_DIR/Portside.app"
rm -f "$BUILD_DIR/Portside-${VERSION}.dmg" "$BUILD_DIR/Portside-${VERSION}-notarized.zip"
hdiutil create -volname Portside -srcfolder "$BUILD_DIR/Portside.app" -ov -format UDZO "$BUILD_DIR/Portside-${VERSION}.dmg" >/dev/null
submit_for_notarization "$BUILD_DIR/Portside-${VERSION}.dmg"
xcrun stapler staple "$BUILD_DIR/Portside-${VERSION}.dmg"
xcrun stapler validate "$BUILD_DIR/Portside-${VERSION}.dmg"
ditto -c -k --sequesterRsrc --keepParent "$BUILD_DIR/Portside.app" "$BUILD_DIR/Portside-${VERSION}-notarized.zip"
shasum -a 256 "$BUILD_DIR/Portside-${VERSION}-notarized.zip" >> "$BUILD_DIR/checksums.txt"
shasum -a 256 "$BUILD_DIR/Portside-${VERSION}.dmg" >> "$BUILD_DIR/checksums.txt"
