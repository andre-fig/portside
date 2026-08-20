#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
CHANNEL="${PORTSIDE_RUNTIME_CHANNEL:-staging}"
DOWNLOAD_URL_PREFIX="${PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX:-${PORTSIDE_RUNTIME_ARTIFACT_URL_PREFIX:-}}"
PORTSIDE_COMMIT="${PORTSIDE_COMMIT:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"

case "$CHANNEL" in staging|production) ;; *) echo "runtime channel must be staging or production" >&2; exit 1 ;; esac
case "$BUILD_DIR" in "$ROOT_DIR"/*) ;; *) echo "runtime build directory must be inside the checkout" >&2; exit 1 ;; esac
command -v jq >/dev/null 2>&1 || { echo "jq is required for the Portside runtime build" >&2; exit 1; }

mkdir -p "$BUILD_DIR"
"$ROOT_DIR/scripts/build-runtime/source-audit.sh"
"$ROOT_DIR/scripts/build-runtime/build-wrapper.sh"
"$ROOT_DIR/scripts/build-runtime/build-wine-engine.sh"
"$ROOT_DIR/scripts/build-runtime/build-winetricks.sh"
"$ROOT_DIR/scripts/build-runtime/validate-clean-layout.sh"

wrapper_file="PortsideWrapper-$VERSION.tar.xz"
engine_file="PortsideWineEngine-$VERSION.tar.xz"
winetricks_file="PortsideWinetricks-$VERSION.tar.xz"
for artifact in "$wrapper_file" "$engine_file" "$winetricks_file"; do
    [ -s "$BUILD_DIR/$artifact" ] || { echo "required runtime artifact was not produced: $artifact" >&2; exit 1; }
    case "$artifact" in *Sikarugir*|*Template*) echo "legacy artifact name produced: $artifact" >&2; exit 1 ;; esac
done

wine_commit="$(jq -r '.repositories[] | select(.name == "wine") | .commit' "$ROOT_DIR/upstream/lock.json")"
wine_checksum="$(jq -r '.repositories[] | select(.name == "wine") | .snapshotChecksum' "$ROOT_DIR/upstream/lock.json")"
winetricks_commit="$(jq -r '.repositories[] | select(.name == "winetricks") | .commit' "$ROOT_DIR/upstream/lock.json")"
winetricks_checksum="$(jq -r '.repositories[] | select(.name == "winetricks") | .snapshotChecksum' "$ROOT_DIR/upstream/lock.json")"
wrapper_source_root="$BUILD_DIR/source-checksums"
rm -rf "$wrapper_source_root"
mkdir -p "$wrapper_source_root"
cp -R "$ROOT_DIR/runtime/wrapper-template" "$wrapper_source_root/"
cp -R "$ROOT_DIR/apps/runtime-host" "$wrapper_source_root/"
wrapper_source_checksum="$($ROOT_DIR/scripts/upstream/snapshot_checksum.sh "$wrapper_source_root")"
rm -rf "$wrapper_source_root"
wrapper_checksum="$(shasum -a 256 "$BUILD_DIR/$wrapper_file" | awk '{print $1}')"
engine_checksum="$(shasum -a 256 "$BUILD_DIR/$engine_file" | awk '{print $1}')"
winetricks_artifact_checksum="$(shasum -a 256 "$BUILD_DIR/$winetricks_file" | awk '{print $1}')"
wrapper_size="$(wc -c < "$BUILD_DIR/$wrapper_file" | tr -d '[:space:]')"
engine_size="$(wc -c < "$BUILD_DIR/$engine_file" | tr -d '[:space:]')"
winetricks_size="$(wc -c < "$BUILD_DIR/$winetricks_file" | tr -d '[:space:]')"
build_id="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
published_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$BUILD_DIR/provenance.json" <<EOF
{
  "schemaVersion": 1,
  "buildId": "$build_id",
  "portsideCommit": "$PORTSIDE_COMMIT",
  "channel": "$CHANNEL",
  "version": "$VERSION",
  "sourcePolicy": "checked-in vendor sources only; no compiled upstream input",
  "sourceCommits": {"portside": "$PORTSIDE_COMMIT", "wine": "$wine_commit", "winetricks": "$winetricks_commit"},
  "sourceSnapshotChecksums": {"portsideWrapper": "$wrapper_source_checksum", "wine": "$wine_checksum", "winetricks": "$winetricks_checksum"},
  "artifacts": ["$wrapper_file", "$engine_file", "$winetricks_file"]
}
EOF

url_for() {
    case "$DOWNLOAD_URL_PREFIX" in */) printf '%s%s' "$DOWNLOAD_URL_PREFIX" "$1" ;; *) printf '%s/%s' "$DOWNLOAD_URL_PREFIX" "$1" ;; esac
}
wrapper_url="$(url_for "$wrapper_file")"
engine_url="$(url_for "$engine_file")"
winetricks_url="$(url_for "$winetricks_file")"

jq -n \
  --arg version "$VERSION" \
  --arg buildId "$build_id" \
  --arg portsideCommit "$PORTSIDE_COMMIT" \
  --arg channel "$CHANNEL" \
  --arg publishedAt "$published_at" \
  --arg wrapperURL "$wrapper_url" --arg wrapperSHA "$wrapper_checksum" --arg wrapperSize "$wrapper_size" \
  --arg engineURL "$engine_url" --arg engineSHA "$engine_checksum" --arg engineSize "$engine_size" \
  --arg winetricksURL "$winetricks_url" --arg winetricksSHA "$winetricks_artifact_checksum" --arg winetricksSize "$winetricks_size" \
  --arg wineCommit "$wine_commit" --arg wineChecksum "$wine_checksum" \
  --arg winetricksCommit "$winetricks_commit" --arg winetricksChecksum "$winetricks_checksum" --arg wrapperSourceChecksum "$wrapper_source_checksum" \
  '{schemaVersion: 2, channel: $channel, manifestVersion: $version, minimumPortsideVersion: "0.1.0", publishedAt: $publishedAt, buildStatus: $channel, builtBy: "Portside", buildId: $buildId, portsideCommit: $portsideCommit, components: [
    {id: "wrapper", component: "wrapper", version: $version, downloadURL: $wrapperURL, sha256: $wrapperSHA, size: ($wrapperSize|tonumber), critical: true, rollbackVersion: null, builtBy: "Portside", sourcePath: "runtime/wrapper-template + apps/runtime-host", sourceCommit: $portsideCommit, sourceSnapshotChecksum: $wrapperSourceChecksum, license: "Portside runtime host and template"},
    {id: "engine", component: "engine", version: $version, downloadURL: $engineURL, sha256: $engineSHA, size: ($engineSize|tonumber), critical: true, rollbackVersion: null, builtBy: "Portside", sourcePath: "vendor/wine", sourceCommit: $wineCommit, sourceSnapshotChecksum: $wineChecksum, license: "LGPL-2.1-or-later"},
    {id: "winetricks", component: "winetricks", version: $version, downloadURL: $winetricksURL, sha256: $winetricksSHA, size: ($winetricksSize|tonumber), critical: true, rollbackVersion: null, builtBy: "Portside", sourcePath: "vendor/winetricks", sourceCommit: $winetricksCommit, sourceSnapshotChecksum: $winetricksChecksum, license: "LGPL-2.1-or-later"}
  ], rendererDefaults: {renderer: "wineD3D", D3DMETAL: 0, DXMT: 0, DXVK: 0, WINEMSYNC: 1, WINEESYNC: 1}, compatibilityRules: [], critical: true, rollbackVersion: null, signatureKeyId: "", signature: null}' \
  > "$BUILD_DIR/runtime-manifest-unsigned.json"

jq -n \
  --arg version "$VERSION" --arg wineCommit "$wine_commit" --arg wineChecksum "$wine_checksum" --arg winetricksCommit "$winetricks_commit" --arg winetricksChecksum "$winetricks_checksum" --arg wrapperSHA "$wrapper_checksum" --arg engineSHA "$engine_checksum" --arg winetricksSHA "$winetricks_artifact_checksum" \
  '{spdxVersion: "SPDX-2.3", dataLicense: "CC0-1.0", SPDXID: "SPDXRef-DOCUMENT", name: ("Portside runtime " + $version), documentNamespace: ("https://portside.invalid/sbom/" + $version), packages: [
    {SPDXID: "SPDXRef-wrapper", name: "Portside wrapper", versionInfo: $version, downloadLocation: "NOASSERTION", licenseConcluded: "NOASSERTION", supplier: "Portside", checksums: [{algorithm: "SHA256", checksumValue: $wrapperSHA}]},
    {SPDXID: "SPDXRef-wine", name: "Wine", versionInfo: $version, downloadLocation: "NOASSERTION", licenseConcluded: "LGPL-2.1-or-later", supplier: "Portside", checksums: [{algorithm: "SHA256", checksumValue: $engineSHA}], externalRefs: [{referenceType: "source-commit", referenceLocator: $wineCommit}, {referenceType: "source-snapshot-sha256", referenceLocator: $wineChecksum}]},
    {SPDXID: "SPDXRef-winetricks", name: "Winetricks", versionInfo: $version, downloadLocation: "NOASSERTION", licenseConcluded: "LGPL-2.1-or-later", supplier: "Portside", checksums: [{algorithm: "SHA256", checksumValue: $winetricksSHA}], externalRefs: [{referenceType: "source-commit", referenceLocator: $winetricksCommit}, {referenceType: "source-snapshot-sha256", referenceLocator: $winetricksChecksum}]}
  ]}' > "$BUILD_DIR/sbom.spdx.json"

if [ -z "$DOWNLOAD_URL_PREFIX" ]; then
    echo "Runtime archives were built, but PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX is required to create a publishable manifest." >&2
    exit 2
fi
case "$DOWNLOAD_URL_PREFIX" in https://*) ;; *) echo "runtime download URL prefix must use HTTPS" >&2; exit 1 ;; esac
"$ROOT_DIR/scripts/build-runtime/validate-manifest.sh" "$BUILD_DIR/runtime-manifest-unsigned.json"
echo "Built Portside runtime artifacts and unsigned staging manifest in $BUILD_DIR."
