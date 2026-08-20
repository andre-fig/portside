#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
SOURCE_DIR="$ROOT_DIR/vendor/winetricks"
STAGE="$BUILD_DIR/work/winetricks/PortsideWinetricks-$VERSION"
ARCHIVE="$BUILD_DIR/PortsideWinetricks-$VERSION.tar.xz"

"$ROOT_DIR/scripts/upstream/validate_snapshot.sh" "$SOURCE_DIR"
[ -f "$SOURCE_DIR/src/winetricks" ] || { echo "vendor/winetricks/src/winetricks is missing" >&2; exit 1; }
case "$BUILD_DIR" in "$ROOT_DIR"/*) ;; *) echo "runtime build directory must be inside the checkout" >&2; exit 1 ;; esac

rm -rf "$BUILD_DIR/work/winetricks"
mkdir -p "$STAGE"
cp -R "$SOURCE_DIR/." "$STAGE/"
chmod 755 "$STAGE/src/winetricks"
rm -f "$ARCHIVE"
"$ROOT_DIR/scripts/build-runtime/create-archive.sh" "$ARCHIVE" "$BUILD_DIR/work/winetricks" "PortsideWinetricks-$VERSION"
shasum -a 256 "$ARCHIVE" | awk '{print $1 "  " $2}' > "$BUILD_DIR/PortsideWinetricks-$VERSION.sha256"
echo "Built $ARCHIVE from the vendored Winetricks source."
