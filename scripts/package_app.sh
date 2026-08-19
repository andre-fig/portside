#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Portside.app"
DSYM_DIR="$BUILD_DIR/Portside.app.dSYM"
ICONSET_DIR="$BUILD_DIR/Portside.iconset"

swift build -c release --arch arm64 --product Portside --package-path "$ROOT_DIR"
rm -rf "$APP_DIR"
rm -rf "$DSYM_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/arm64-apple-macosx/release/Portside" "$APP_DIR/Contents/MacOS/Portside"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/PortsideLogo.png" "$APP_DIR/Contents/Resources/PortsideLogo.png"
mkdir -p "$ICONSET_DIR"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT_DIR/Resources/PortsideLogo.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$ROOT_DIR/Resources/PortsideLogo.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/PortsideIcon.icns"
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

echo "Created $APP_DIR"
echo "Created $DSYM_DIR"
