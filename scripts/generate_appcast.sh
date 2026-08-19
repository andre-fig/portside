#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UPDATES_DIR="${PORTSIDE_UPDATES_DIR:-$ROOT_DIR/build/releases/updates}"
SPARKLE_BIN="${SPARKLE_BIN:?Set SPARKLE_BIN to the Sparkle 2 bin directory from CI/Xcode}"
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Sparkle generate_appcast not found" >&2; exit 1; }
[ -d "$UPDATES_DIR" ] || { echo "Missing update archive directory $UPDATES_DIR" >&2; exit 1; }
"$SPARKLE_BIN/generate_appcast" "$UPDATES_DIR"
[ -f "$UPDATES_DIR/appcast.xml" ] || { echo "Sparkle did not produce appcast.xml" >&2; exit 1; }
cp "$UPDATES_DIR/appcast.xml" "${PORTSIDE_APPCAST_OUTPUT:-$ROOT_DIR/build/releases/appcast.xml}"
