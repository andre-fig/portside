#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UPDATES_DIR="${PORTSIDE_UPDATES_DIR:-$ROOT_DIR/build/releases/updates}"
SPARKLE_BIN="${SPARKLE_BIN:?Set SPARKLE_BIN to the Sparkle 2 bin directory from CI/Xcode}"
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Sparkle generate_appcast not found" >&2; exit 1; }
[ -d "$UPDATES_DIR" ] || { echo "Missing update archive directory $UPDATES_DIR" >&2; exit 1; }
KEY_FILE="${PORTSIDE_SPARKLE_PRIVATE_KEY_FILE:?Set the CI-only Sparkle EdDSA private key file outside the repository}"
[ -f "$KEY_FILE" ] || { echo "Missing Sparkle EdDSA private key" >&2; exit 1; }
case "$KEY_FILE" in "$ROOT_DIR"/*) echo "Sparkle signing keys must remain outside the repository" >&2; exit 1;; esac
APPCAST_ARGS="--ed-key-file $KEY_FILE --maximum-versions 3 --channel ${PORTSIDE_UPDATE_CHANNEL:-staging}"
if [ -n "${PORTSIDE_DOWNLOAD_URL_PREFIX:-}" ]; then APPCAST_ARGS="$APPCAST_ARGS --download-url-prefix ${PORTSIDE_DOWNLOAD_URL_PREFIX}"; fi
if [ -n "${PORTSIDE_RELEASE_NOTES_URL_PREFIX:-}" ]; then APPCAST_ARGS="$APPCAST_ARGS --release-notes-url-prefix ${PORTSIDE_RELEASE_NOTES_URL_PREFIX}"; fi
# shellcheck disable=SC2086
"$SPARKLE_BIN/generate_appcast" $APPCAST_ARGS "$UPDATES_DIR"
[ -f "$UPDATES_DIR/appcast.xml" ] || { echo "Sparkle did not produce appcast.xml" >&2; exit 1; }
OUTPUT="${PORTSIDE_APPCAST_OUTPUT:-$ROOT_DIR/build/releases/appcast.xml}"
cp "$UPDATES_DIR/appcast.xml" "$OUTPUT"
grep -q 'sparkle:edSignature=' "$OUTPUT" || { echo "Generated appcast has no EdDSA release signature" >&2; exit 1; }
if grep -q 'example\.invalid' "$OUTPUT"; then echo "Generated appcast contains a placeholder URL" >&2; exit 1; fi
