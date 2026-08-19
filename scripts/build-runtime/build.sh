#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
VERSION="${PORTSIDE_RUNTIME_VERSION:-source-$(date -u +%Y%m%d)}"

mkdir -p "$BUILD_DIR"
"$ROOT_DIR/scripts/upstream/validate_snapshot.sh" "$ROOT_DIR/vendor/wine"
"$ROOT_DIR/scripts/upstream/validate_snapshot.sh" "$ROOT_DIR/vendor/winetricks"

# This is a Portside-produced source artifact. It is deliberately made from
# the checked-in tree and never downloaded from a release URL.
WINETRICKS_ARCHIVE="$BUILD_DIR/PortsideWinetricks-$VERSION.tar.xz"
tar -cJf "$WINETRICKS_ARCHIVE" -C "$ROOT_DIR/vendor/winetricks" .
artifact_sha256=$(shasum -a 256 "$WINETRICKS_ARCHIVE" | awk '{print $1}')
artifact_size=$(wc -c < "$WINETRICKS_ARCHIVE" | tr -d '[:space:]')

wine_commit=$(jq -r '.repositories[] | select(.name == "wine") | .commit' "$ROOT_DIR/upstream/lock.json")
winetricks_commit=$(jq -r '.repositories[] | select(.name == "winetricks") | .commit' "$ROOT_DIR/upstream/lock.json")
wine_checksum=$(jq -r '.repositories[] | select(.name == "wine") | .snapshotChecksum' "$ROOT_DIR/upstream/lock.json")
winetricks_checksum=$(jq -r '.repositories[] | select(.name == "winetricks") | .snapshotChecksum' "$ROOT_DIR/upstream/lock.json")
winetricks_repository=$(jq -r '.repositories[] | select(.name == "winetricks") | .repository' "$ROOT_DIR/upstream/lock.json")
macos_version=$(sw_vers -productVersion 2>/dev/null || uname -sr)
architecture=$(uname -m)
xcode_version=$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || true)
swift_version=$(swift --version 2>/dev/null | head -1 || true)

jq -n \
  --arg artifact "PortsideWinetricks-$VERSION.tar.xz" \
  --arg version "$VERSION" \
  --arg sha256 "$artifact_sha256" \
  --arg size "$artifact_size" \
  --arg sourceRepository "$winetricks_repository" \
  --arg sourceCommit "$winetricks_commit" \
  --arg sourceSnapshotChecksum "$winetricks_checksum" \
  '{spdxVersion: "SPDX-2.3", dataLicense: "CC0-1.0", SPDXID: "SPDXRef-DOCUMENT", name: ("Portside runtime " + $version), documentNamespace: ("https://portside.invalid/sbom/" + $version), packages: [{SPDXID: "SPDXRef-winetricks", name: "winetricks", versionInfo: $version, downloadLocation: $sourceRepository, licenseConcluded: "LGPL-2.1-or-later", supplier: "Portside", checksums: [{algorithm: "SHA256", checksumValue: $sha256}], externalRefs: [{referenceType: "source-commit", referenceLocator: $sourceCommit}, {referenceType: "source-snapshot-sha256", referenceLocator: $sourceSnapshotChecksum}], annotations: [{annotationType: "OTHER", annotator: "Tool: Portside", comment: ("artifact=" + $artifact + "; size=" + $size)}]}]}' \
  > "$BUILD_DIR/sbom.spdx.json"

jq -n \
  --arg version "$VERSION" \
  --arg wineCommit "$wine_commit" \
  --arg wineSnapshotChecksum "$wine_checksum" \
  --arg winetricksCommit "$winetricks_commit" \
  --arg winetricksSnapshotChecksum "$winetricks_checksum" \
  --arg winetricksRepository "$winetricks_repository" \
  --arg artifact "build/runtime/PortsideWinetricks-$VERSION.tar.xz" \
  --arg artifactSHA256 "$artifact_sha256" \
  --arg artifactSize "$artifact_size" \
  --arg macosVersion "$macos_version" \
  --arg architecture "$architecture" \
  --arg xcodeVersion "$xcode_version" \
  --arg swiftVersion "$swift_version" \
  --arg sbom "build/runtime/sbom.spdx.json" \
  '{schemaVersion: 1, version: $version, channel: "staging", status: "partial", artifacts: [{component: "winetricks", path: $artifact, sha256: $artifactSHA256, size: ($artifactSize | tonumber), sourceRepository: $winetricksRepository, sourceCommit: $winetricksCommit, sourceSnapshotChecksum: $winetricksSnapshotChecksum, license: "LGPL-2.1-or-later", sbom: $sbom}], sourceCommits: {wine: $wineCommit, winetricks: $winetricksCommit}, sourceSnapshotChecksums: {wine: $wineSnapshotChecksum, winetricks: $winetricksSnapshotChecksum}, environment: {macOS: $macosVersion, architecture: $architecture, xcode: $xcodeVersion, swift: $swiftVersion, flags: "source-only; no network fetch"}, blockers: ["wrapper source is missing from the pinned Wrapper repository", "engine build recipe and Sikarugir engine patches are missing from the pinned Engines/Wine source set"], note: "No official compiled artifact was used as a fallback."}' \
  > "$BUILD_DIR/provenance.json"

if "$ROOT_DIR/scripts/build-runtime/source-audit.sh" > "$BUILD_DIR/source-audit.txt" 2>&1; then
    cat "$BUILD_DIR/source-audit.txt"
else
    audit_status=$?
    cat "$BUILD_DIR/source-audit.txt"
    echo "Partial runtime output is available at $BUILD_DIR, but the requested wrapper/engine build is blocked." >&2
    exit "$audit_status"
fi

echo "The source audit unexpectedly found all required build inputs; implement the component builders before publishing."
exit 3
