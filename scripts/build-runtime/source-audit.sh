#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"

missing=0
if [ ! -f "$ROOT_DIR/apps/runtime-host/Sources/PortsideRuntimeHost/main.swift" ]; then
    echo "MISSING_SOURCE wrapper: PortsideRuntimeHost source is absent"
    missing=1
fi
if [ ! -f "$ROOT_DIR/runtime/wrapper-template/Contents/Info.plist" ]; then
    echo "MISSING_SOURCE wrapper: Portside wrapper template is absent"
    missing=1
fi
for component in wrapper engines; do
    if [ ! -d "$VENDOR_DIR/$component" ]; then
        echo "MISSING_SOURCE provenance: vendor/$component is absent"
        missing=1
    fi
done

if [ ! -f "$VENDOR_DIR/wine/configure.ac" ]; then
    echo "MISSING_SOURCE wine: configure.ac is absent"
    missing=1
fi
if [ ! -f "$VENDOR_DIR/winetricks/src/winetricks" ]; then
    echo "MISSING_SOURCE winetricks: src/winetricks is absent"
    missing=1
fi

if [ "$missing" -ne 0 ]; then
    echo "Runtime source audit blocked: Portside build inputs are incomplete." >&2
    exit 2
fi

echo "Runtime source audit passed."
