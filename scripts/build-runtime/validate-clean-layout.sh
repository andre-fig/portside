#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/portside-runtime-layout.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT INT TERM

for archive in \
    "$BUILD_DIR/PortsideWrapper-$VERSION.tar.xz" \
    "$BUILD_DIR/PortsideWineEngine-$VERSION.tar.xz" \
    "$BUILD_DIR/PortsideWinetricks-$VERSION.tar.xz"; do
    [ -s "$archive" ] || { echo "missing runtime archive: $archive" >&2; exit 1; }
    tar -tJf "$archive" >/dev/null
    tar -xJf "$archive" -C "$TEMP_ROOT"
done

wrapper="$TEMP_ROOT/PortsideBaseline.app"
[ -f "$wrapper/Contents/Info.plist" ] || { echo "wrapper Info.plist is missing" >&2; exit 1; }
[ -x "$wrapper/Contents/MacOS/PortsideRuntimeHost" ] || { echo "PortsideRuntimeHost is missing" >&2; exit 1; }

engine="$TEMP_ROOT/PortsideWineEngine-$VERSION"
for executable in wine wineboot wineserver; do
    [ -x "$engine/bin/$executable" ] || { echo "engine executable is missing: $executable" >&2; exit 1; }
done
[ -d "$engine/share-wine" ] || { echo "engine share-wine directory is missing" >&2; exit 1; }

winetricks="$TEMP_ROOT/PortsideWinetricks-$VERSION"
[ -x "$winetricks/src/winetricks" ] || { echo "winetricks source is missing" >&2; exit 1; }

if find "$TEMP_ROOT" -type f \( -iname '*Sikarugir*' -o -iname 'Template-*' \) -print -quit | grep -q .; then
    echo "legacy runtime artifact found in clean layout" >&2
    exit 1
fi

echo "Clean runtime layout validation passed."
