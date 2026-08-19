#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DESKTOP_DIR="$ROOT_DIR/apps/desktop"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
APP_DIR="$BUILD_DIR/Portside.app"
IDENTITY="${PORTSIDE_CODESIGN_IDENTITY:?Set PORTSIDE_CODESIGN_IDENTITY to a Developer ID Application identity}"
[ "$IDENTITY" != "-" ] || { echo "Ad hoc signing is forbidden for commercial releases" >&2; exit 1; }
[ -d "$APP_DIR" ] || { echo "Missing $APP_DIR; run build_release.sh first" >&2; exit 1; }
export PORTSIDE_MANIFEST_OUTPUT="${PORTSIDE_MANIFEST_OUTPUT:-$BUILD_DIR/runtime-manifest.json}"
"$ROOT_DIR/scripts/generate_manifest.sh"
security find-identity -v -p codesigning | grep -F "$IDENTITY" | grep -F 'Developer ID Application' >/dev/null || { echo "Developer ID Application identity not found" >&2; exit 1; }

if [ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]; then
    find "$APP_DIR/Contents/Frameworks/Sparkle.framework" -type d \( -name '*.app' -o -name '*.xpc' \) -exec codesign --force --options runtime --timestamp --sign "$IDENTITY" {} \;
    find "$APP_DIR/Contents/Frameworks/Sparkle.framework" -type f -perm -111 -exec codesign --force --options runtime --timestamp --sign "$IDENTITY" {} \;
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
fi
HELPER_APP="$APP_DIR/Contents/Helpers/PortsideAgent.app"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$HELPER_APP/Contents/MacOS/PortsideAgent"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$HELPER_APP"
codesign --force --options runtime --timestamp --entitlements "$DESKTOP_DIR/Resources/Portside.entitlements" --sign "$IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$BUILD_DIR/Portside-${PORTSIDE_VERSION:?Set PORTSIDE_VERSION}.zip"
shasum -a 256 "$BUILD_DIR/Portside-${PORTSIDE_VERSION}.zip" > "$BUILD_DIR/checksums.txt"
shasum -a 256 "$PORTSIDE_MANIFEST_OUTPUT" >> "$BUILD_DIR/checksums.txt"
echo "Signed and archived $APP_DIR"
