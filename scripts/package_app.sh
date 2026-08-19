#!/bin/sh
set -eu
# This script intentionally creates a local/development bundle. Commercial
# builds must use build_release.sh so feed, API and public keys are injected
# from a protected CI environment before signing and notarization.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DESKTOP_DIR="$ROOT_DIR/apps/desktop"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Portside.app"
DSYM_DIR="$BUILD_DIR/Portside.app.dSYM"
ICONSET_DIR="$BUILD_DIR/Portside.iconset"

swift build -c release --arch arm64 --product Portside --package-path "$DESKTOP_DIR"
swift build -c release --arch arm64 --product PortsideAgent --package-path "$DESKTOP_DIR"
rm -rf "$APP_DIR"
rm -rf "$DSYM_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/MacOS"
cp "$DESKTOP_DIR/.build/arm64-apple-macosx/release/Portside" "$APP_DIR/Contents/MacOS/Portside"
cp "$DESKTOP_DIR/.build/arm64-apple-macosx/release/PortsideAgent" "$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/MacOS/PortsideAgent"
cp "$DESKTOP_DIR/Resources/PortsideAgent-Info.plist" "$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/Info.plist"
cp "$DESKTOP_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$DESKTOP_DIR/Resources/PortsideLogo.png" "$APP_DIR/Contents/Resources/PortsideLogo.png"
SPARKLE_FRAMEWORK="$DESKTOP_DIR/.build/arm64-apple-macosx/release/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "Sparkle.framework was not produced by SwiftPM" >&2; exit 1; }
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_DIR/Contents/MacOS/Portside" 2>/dev/null || true
mkdir -p "$ICONSET_DIR"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$DESKTOP_DIR/Resources/PortsideLogo.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$DESKTOP_DIR/Resources/PortsideLogo.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/PortsideIcon.icns"
/usr/libexec/PlistBuddy -c "Set :PortsideBuildChannel development" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :PortsideBuildChannel development" "$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/Portside"
dsymutil "$APP_DIR/Contents/MacOS/Portside" -o "$DSYM_DIR"

SIGNING_IDENTITY="${PORTSIDE_CODESIGN_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [ -n "${SENTRY_AUTH_TOKEN:-}" ] && command -v sentry-cli >/dev/null 2>&1; then
    sentry-cli debug-files upload "$DSYM_DIR"
fi

echo "Created local development bundle $APP_DIR (not a commercial release)"
echo "Created $DSYM_DIR"
