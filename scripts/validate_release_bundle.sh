#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
APP_DIR="$BUILD_DIR/Portside.app"
VERSION="${PORTSIDE_VERSION:?Set PORTSIDE_VERSION}"
[ -d "$APP_DIR" ] || { echo "Missing production app bundle" >&2; exit 1; }

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$APP_DIR/Contents/Info.plist" 2>/dev/null
}

for key in PortsideAPIBaseURL SUFeedURL SUPublicEDKey PortsideArtifactHosts PortsideRuntimeManifestPublicKey PortsideLicensePublicKey PortsideLicenseKeyID SUEnableAutomaticChecks SUAutomaticallyUpdate SUVerifyUpdateBeforeExtraction; do
    value="$(plist_value "$key")"
    case "$value" in ""|*example.invalid*) echo "Production Info.plist has an invalid $key" >&2; exit 1;; esac
done
[ "$(plist_value PortsideBuildChannel)" = production ] || { echo "Production bundle must declare production" >&2; exit 1; }
[ "$(plist_value CFBundleShortVersionString)" = "$VERSION" ] || { echo "Bundle version does not match release version" >&2; exit 1; }

HELPER="$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/Info.plist"
for key in PortsideAPIBaseURL PortsideArtifactHosts PortsideRuntimeManifestPublicKey; do
    main_value="$(plist_value "$key")"
    helper_value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$HELPER")"
    [ "$main_value" = "$helper_value" ] || { echo "Helper configuration differs for $key" >&2; exit 1; }
done

codesign --verify --deep --strict "$APP_DIR"

DMG="$BUILD_DIR/Portside-${VERSION}.dmg"
[ -f "$DMG" ] || { echo "Missing production DMG" >&2; exit 1; }
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/portside-dmg.XXXXXX")"
cleanup() {
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
DMG_PLIST="$MOUNT_POINT/Portside.app/Contents/Info.plist"
[ -f "$DMG_PLIST" ] || { echo "DMG does not contain Portside.app" >&2; exit 1; }
extra_entry="$(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 ! -name 'Portside.app' -print -quit)"
[ -z "$extra_entry" ] || { echo "DMG contains an unexpected top-level entry: $(basename "$extra_entry")" >&2; exit 1; }
for key in PortsideAPIBaseURL SUFeedURL SUPublicEDKey PortsideArtifactHosts PortsideRuntimeManifestPublicKey PortsideLicensePublicKey PortsideLicenseKeyID; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$DMG_PLIST")"
    case "$value" in ""|*example.invalid*) echo "Production DMG has an invalid $key" >&2; exit 1;; esac
done
echo "Production bundle configuration is complete and signed."
