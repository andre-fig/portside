#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Portside.app"

swift build -c release --arch arm64 --package-path "$ROOT_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/arm64-apple-macosx/release/Portside" "$APP_DIR/Contents/MacOS/Portside"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/Portside"
codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
