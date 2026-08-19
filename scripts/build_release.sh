#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DESKTOP_DIR="$ROOT_DIR/apps/desktop"
BUILD_DIR="${PORTSIDE_BUILD_DIR:-$ROOT_DIR/build/releases}"
VERSION="${PORTSIDE_VERSION:?Set PORTSIDE_VERSION, for example 1.0.0}"
API_URL="${PORTSIDE_API_BASE_URL:?Set the Portside HTTPS API URL}"
FEED_URL="${PORTSIDE_UPDATE_FEED_URL:?Set the Portside HTTPS Sparkle feed URL}"
SPARKLE_KEY="${PORTSIDE_SPARKLE_PUBLIC_KEY:?Set the Sparkle Ed25519 public key}"
MANIFEST_KEY="${PORTSIDE_RUNTIME_MANIFEST_PUBLIC_KEY:?Set the runtime manifest Ed25519 public key}"
LICENSE_KEY="${PORTSIDE_LICENSE_PUBLIC_KEY:?Set the license-token Ed25519 public key}"
LICENSE_KEY_ID="${PORTSIDE_LICENSE_KEY_ID:?Set the license signing key ID}"
ARTIFACT_HOSTS="${PORTSIDE_ARTIFACT_HOSTS:?Set comma-separated Portside object-storage hosts}"
CHANNEL="${PORTSIDE_UPDATE_CHANNEL:-staging}"

case "$CHANNEL" in staging|production) ;; *) echo "PORTSIDE_UPDATE_CHANNEL must be staging or production" >&2; exit 1;; esac
for value in "$API_URL" "$FEED_URL" "$SPARKLE_KEY" "$MANIFEST_KEY" "$LICENSE_KEY" "$LICENSE_KEY_ID" "$ARTIFACT_HOSTS"; do
    case "$value" in ""|*example.invalid*) echo "Release configuration contains an empty or placeholder value" >&2; exit 1;; esac
done
case "$API_URL:$FEED_URL" in *:http://*|http://*) echo "Release URLs must use HTTPS" >&2; exit 1;; esac
APP_DIR="$BUILD_DIR/Portside.app"
DSYM_DIR="$BUILD_DIR/Portside.app.dSYM"
ICONSET_DIR="$BUILD_DIR/Portside.iconset"
BIN_PATH="$DESKTOP_DIR/.build/arm64-apple-macosx/release"

swift build -c release --arch arm64 --product Portside --package-path "$DESKTOP_DIR"
swift build -c release --arch arm64 --product PortsideAgent --package-path "$DESKTOP_DIR"
rm -rf "$APP_DIR" "$DSYM_DIR" "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/MacOS"
cp "$BIN_PATH/Portside" "$APP_DIR/Contents/MacOS/Portside"
cp "$BIN_PATH/PortsideAgent" "$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/MacOS/PortsideAgent"
cp "$DESKTOP_DIR/Resources/PortsideAgent-Info.plist" "$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/Info.plist"
cp "$DESKTOP_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$DESKTOP_DIR/Resources/PortsideLogo.png" "$APP_DIR/Contents/Resources/PortsideLogo.png"
mkdir -p "$ICONSET_DIR"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$DESKTOP_DIR/Resources/PortsideLogo.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$DESKTOP_DIR/Resources/PortsideLogo.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/PortsideIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :PortsideAPIBaseURL $API_URL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :PortsideArtifactHosts $ARTIFACT_HOSTS" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $FEED_URL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_KEY" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :PortsideRuntimeManifestPublicKey $MANIFEST_KEY" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :PortsideLicensePublicKey $LICENSE_KEY" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :PortsideLicenseKeyID $LICENSE_KEY_ID" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :PortsideBuildChannel $CHANNEL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUAutomaticallyUpdate true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUScheduledCheckInterval 86400" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUScheduledImpatientCheckInterval 604800" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUVerifyUpdateBeforeExtraction true" "$APP_DIR/Contents/Info.plist"

# The background helper must carry the same public configuration because it
# continues runtime staging after Portside.app exits. It never receives a
# private signing key.
AGENT_PLIST="$APP_DIR/Contents/Helpers/PortsideAgent.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$AGENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$AGENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :PortsideAPIBaseURL $API_URL" "$AGENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :PortsideArtifactHosts $ARTIFACT_HOSTS" "$AGENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :PortsideRuntimeManifestPublicKey $MANIFEST_KEY" "$AGENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :PortsideBuildChannel $CHANNEL" "$AGENT_PLIST"

if [ -d "$BIN_PATH/Sparkle.framework" ]; then
    cp -R "$BIN_PATH/Sparkle.framework" "$APP_DIR/Contents/Frameworks/"
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_DIR/Contents/MacOS/Portside" 2>/dev/null || true
else
    echo "Sparkle.framework was not produced by SwiftPM" >&2
    exit 1
fi
chmod +x "$APP_DIR/Contents/MacOS/Portside"
dsymutil "$APP_DIR/Contents/MacOS/Portside" -o "$DSYM_DIR"
rm -rf "$ICONSET_DIR"
echo "Built unsigned release bundle at $APP_DIR"
echo "Next: PORTSIDE_CODESIGN_IDENTITY='Developer ID Application: …' scripts/sign_release.sh"
