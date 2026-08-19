#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
VERSION="${PORTSIDE_VERSION:?Set PORTSIDE_VERSION}"
PROFILE="${PORTSIDE_NOTARY_PROFILE:?Set a notarytool keychain profile name; never put credentials in Git}"
ZIP="$BUILD_DIR/Portside-${VERSION}.zip"
[ -f "$ZIP" ] || { echo "Missing signed archive $ZIP" >&2; exit 1; }
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$BUILD_DIR/Portside.app"
xcrun stapler validate "$BUILD_DIR/Portside.app"
codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/Portside.app"
spctl --assess --type execute --verbose=4 "$BUILD_DIR/Portside.app"
rm -f "$BUILD_DIR/Portside-${VERSION}.dmg" "$BUILD_DIR/Portside-${VERSION}-notarized.zip"
hdiutil create -volname Portside -srcfolder "$BUILD_DIR/Portside.app" -ov -format UDZO "$BUILD_DIR/Portside-${VERSION}.dmg" >/dev/null
xcrun notarytool submit "$BUILD_DIR/Portside-${VERSION}.dmg" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$BUILD_DIR/Portside-${VERSION}.dmg"
xcrun stapler validate "$BUILD_DIR/Portside-${VERSION}.dmg"
ditto -c -k --sequesterRsrc --keepParent "$BUILD_DIR/Portside.app" "$BUILD_DIR/Portside-${VERSION}-notarized.zip"
shasum -a 256 "$BUILD_DIR/Portside-${VERSION}-notarized.zip" >> "$BUILD_DIR/checksums.txt"
shasum -a 256 "$BUILD_DIR/Portside-${VERSION}.dmg" >> "$BUILD_DIR/checksums.txt"
