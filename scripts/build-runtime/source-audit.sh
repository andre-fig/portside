#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"

source_markers() {
    find "$1" -type f \( \
        -name configure.ac -o \
        -name CMakeLists.txt -o \
        -name Package.swift -o \
        -name Makefile.am -o \
        -name '*.xcodeproj' -o \
        -name '*.xcworkspace' \
    \) -print -quit
}

missing=0
for component in wrapper engines; do
    component_dir="$VENDOR_DIR/$component"
    if [ ! -d "$component_dir" ]; then
        echo "MISSING_SOURCE $component: vendor directory is absent"
        missing=1
        continue
    fi
    if ! source_markers "$component_dir" | grep -q .; then
        echo "MISSING_SOURCE $component: no source/build marker exists in $component_dir"
        find "$component_dir" -maxdepth 2 -type f -print | sed 's#^#  available: #' | head -30
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
    echo "Runtime source audit blocked: the pinned upstream set cannot reproduce the requested wrapper and engine." >&2
    exit 2
fi

echo "Runtime source audit passed."
