#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
TEMPLATE_DIR="$ROOT_DIR/runtime/wrapper-template"
HOST_SOURCE="$ROOT_DIR/apps/runtime-host/Sources/PortsideRuntimeHost/main.swift"
STAGE="$BUILD_DIR/work/wrapper/PortsideBaseline.app"
ARCHIVE="$BUILD_DIR/PortsideWrapper-$VERSION.tar.xz"

case "$BUILD_DIR" in "$ROOT_DIR"/*) ;; *) echo "runtime build directory must be inside the checkout" >&2; exit 1 ;; esac
[ -f "$TEMPLATE_DIR/Contents/Info.plist" ] || { echo "missing Portside wrapper template" >&2; exit 1; }
[ -f "$HOST_SOURCE" ] || { echo "missing Portside runtime host source" >&2; exit 1; }
command -v swiftc >/dev/null 2>&1 || { echo "swiftc is required to build PortsideRuntimeHost" >&2; exit 1; }
command -v plutil >/dev/null 2>&1 || { echo "plutil is required to configure the wrapper" >&2; exit 1; }

rm -rf "$BUILD_DIR/work/wrapper"
mkdir -p "$BUILD_DIR/work/wrapper" "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp -R "$TEMPLATE_DIR/." "$STAGE/"

swiftc -O -parse-as-library -whole-module-optimization "$HOST_SOURCE" -o "$STAGE/Contents/MacOS/PortsideRuntimeHost"
chmod 755 "$STAGE/Contents/MacOS/PortsideRuntimeHost"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$STAGE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${GITHUB_RUN_NUMBER:-local}" "$STAGE/Contents/Info.plist"
VERSION="$VERSION" CONFIG="$STAGE/Contents/Resources/portside-runtime.json" node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
const path = process.env.CONFIG;
const value = JSON.parse(readFileSync(path, "utf8"));
value.version = process.env.VERSION;
writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
NODE

rm -f "$ARCHIVE"
"$ROOT_DIR/scripts/build-runtime/create-archive.sh" "$ARCHIVE" "$BUILD_DIR/work/wrapper" "PortsideBaseline.app"
shasum -a 256 "$ARCHIVE" | awk '{print $1 "  " $2}' > "$BUILD_DIR/PortsideWrapper-$VERSION.sha256"
echo "Built $ARCHIVE from Portside wrapper sources."
