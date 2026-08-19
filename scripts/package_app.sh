#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Portside.app"
DSYM_DIR="$BUILD_DIR/Portside.app.dSYM"

swift build -c release --arch arm64 --package-path "$ROOT_DIR"
rm -rf "$APP_DIR"
rm -rf "$DSYM_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/arm64-apple-macosx/release/Portside" "$APP_DIR/Contents/MacOS/Portside"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/Portside"
dsymutil "$APP_DIR/Contents/MacOS/Portside" -o "$DSYM_DIR"
codesign --force --deep --sign - "$APP_DIR"

if [ -n "${SENTRY_AUTH_TOKEN:-}" ] && command -v sentry-cli >/dev/null 2>&1; then
    sentry-cli debug-files upload "$DSYM_DIR"
fi

echo "Created $APP_DIR"
echo "Created $DSYM_DIR"
