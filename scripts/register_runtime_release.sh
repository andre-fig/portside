#!/bin/sh
set -eu

BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:?Set PORTSIDE_RUNTIME_BUILD_DIR}"
API_URL="${PORTSIDE_API_BASE_URL:?Set PORTSIDE_API_BASE_URL}"
ADMIN_TOKEN="${PORTSIDE_ADMIN_BEARER_TOKEN:?Set PORTSIDE_ADMIN_BEARER_TOKEN}"
WORKFLOW_RUN_ID="${PORTSIDE_RUNTIME_RUN_ID:?Set PORTSIDE_RUNTIME_RUN_ID}"
LOCK_FILE="${PORTSIDE_UPSTREAM_LOCK_FILE:-upstream/lock.json}"

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[ -s "$BUILD_DIR/runtime-manifest.json" ] || { echo "signed runtime manifest is missing" >&2; exit 1; }
[ -s "$BUILD_DIR/provenance.json" ] || { echo "runtime provenance is missing" >&2; exit 1; }
[ -s "$BUILD_DIR/sbom.spdx.json" ] || { echo "runtime SBOM is missing" >&2; exit 1; }
[ -s "$LOCK_FILE" ] || { echo "upstream lockfile is missing" >&2; exit 1; }

manifest="$BUILD_DIR/runtime-manifest.json"
provenance="$BUILD_DIR/provenance.json"
sbom="$BUILD_DIR/sbom.spdx.json"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/portside-runtime-registration.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT INT TERM

api_post() {
    endpoint="$1"
    body="$2"
    output="$3"
    curl --fail --silent --show-error --retry 3 \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H 'Content-Type: application/json' \
        -d "$body" \
        "$API_URL$endpoint" > "$output"
}

json_id() {
    jq -er '.id | strings | select(length > 0)' "$1"
}

manifest_version="$(jq -er '.manifestVersion | strings' "$manifest")"
manifest_build_id="$(jq -er '.buildId | strings' "$manifest")"
portside_commit="$(jq -er '.portsideCommit | strings | select(test("^[a-fA-F0-9]{40}$"))' "$manifest")"
workflow_url="https://github.com/${GITHUB_REPOSITORY:-andre-fig/portside}/actions/runs/$WORKFLOW_RUN_ID"

register_source_snapshot() {
    source_name="$1"
    repository="$2"
    commit="$3"
    commit_date="$4"
    checksum="$5"
    license="$6"
    local_path="$7"
    submodules="$8"
    lfs_used="$9"
    output="$temp_dir/source-$source_name.json"
    payload="$(jq -n \
        --arg sourceName "$source_name" \
        --arg repository "$repository" \
        --arg commit "$commit" \
        --arg commitDate "$commit_date" \
        --arg snapshotChecksum "$checksum" \
        --arg license "$license" \
        --arg localPath "$local_path" \
        --argjson submodules "$submodules" \
        --argjson lfsUsed "$lfs_used" \
        '{sourceName:$sourceName,repository:$repository,commit:$commit,snapshotChecksum:$snapshotChecksum,license:$license,localPath:$localPath,submodules:$submodules,lfsUsed:$lfsUsed} | if $commitDate == "" then . else .commitDate = $commitDate end')"
    api_post "/v1/admin/source-snapshots/register" "$payload" "$output"
    json_id "$output"
}

wine_repository="$(jq -er '.repositories[] | select(.name == "wine") | .repository' "$LOCK_FILE")"
wine_commit="$(jq -er '.repositories[] | select(.name == "wine") | .commit' "$LOCK_FILE")"
wine_date="$(jq -er '.repositories[] | select(.name == "wine") | .commitDate // ""' "$LOCK_FILE")"
wine_checksum="$(jq -er '.repositories[] | select(.name == "wine") | .snapshotChecksum' "$LOCK_FILE")"
wine_path="$(jq -er '.repositories[] | select(.name == "wine") | .localPath' "$LOCK_FILE")"
wine_submodules="$(jq -c '.repositories[] | select(.name == "wine") | (.submodules // [])' "$LOCK_FILE")"
wine_lfs="$(jq -r '.repositories[] | select(.name == "wine") | (.gitLFSUsed // false)' "$LOCK_FILE")"

winetricks_repository="$(jq -er '.repositories[] | select(.name == "winetricks") | .repository' "$LOCK_FILE")"
winetricks_commit="$(jq -er '.repositories[] | select(.name == "winetricks") | .commit' "$LOCK_FILE")"
winetricks_date="$(jq -r '.repositories[] | select(.name == "winetricks") | .commitDate // ""' "$LOCK_FILE")"
winetricks_checksum="$(jq -er '.repositories[] | select(.name == "winetricks") | .snapshotChecksum' "$LOCK_FILE")"
winetricks_path="$(jq -er '.repositories[] | select(.name == "winetricks") | .localPath' "$LOCK_FILE")"
winetricks_submodules="$(jq -c '.repositories[] | select(.name == "winetricks") | (.submodules // [])' "$LOCK_FILE")"
winetricks_lfs="$(jq -r '.repositories[] | select(.name == "winetricks") | (.gitLFSUsed // false)' "$LOCK_FILE")"

wrapper_checksum="$(jq -er '.components[] | select(.component == "wrapper") | .sourceSnapshotChecksum' "$manifest")"
wrapper_license="$(jq -er '.components[] | select(.component == "wrapper") | .license' "$manifest")"
wine_license="$(jq -er '.components[] | select(.component == "engine") | .license' "$manifest")"
winetricks_license="$(jq -er '.components[] | select(.component == "winetricks") | .license' "$manifest")"
wrapper_snapshot_id="$(register_source_snapshot PortsideWrapper \
    "https://github.com/andre-fig/portside" "$portside_commit" "" "$wrapper_checksum" \
    "$wrapper_license" "runtime/wrapper-template+apps/runtime-host" "[]" false)"
wine_snapshot_id="$(register_source_snapshot SikarugirWine "$wine_repository" "$wine_commit" "$wine_date" "$wine_checksum" "$wine_license" "$wine_path" "$wine_submodules" "$wine_lfs")"
winetricks_snapshot_id="$(register_source_snapshot SikarugirWinetricks "$winetricks_repository" "$winetricks_commit" "$winetricks_date" "$winetricks_checksum" "$winetricks_license" "$winetricks_path" "$winetricks_submodules" "$winetricks_lfs")"

source_snapshot_ids="$(jq -n --arg wrapper "$wrapper_snapshot_id" --arg wine "$wine_snapshot_id" --arg winetricks "$winetricks_snapshot_id" '[$wrapper,$wine,$winetricks]')"
build_output="$temp_dir/build.json"
build_payload="$(jq -n \
    --arg buildId "$manifest_build_id" \
    --arg version "$manifest_version" \
    --arg portsideCommit "$portside_commit" \
    --arg workflowRunId "$WORKFLOW_RUN_ID" \
    --arg workflowURL "$workflow_url" \
    --argjson sourceSnapshotIds "$source_snapshot_ids" \
    --slurpfile provenance "$provenance" \
    --slurpfile sbom "$sbom" \
    '{buildId:$buildId,version:$version,portsideCommit:$portsideCommit,workflowRunId:$workflowRunId,workflowURL:$workflowURL,status:"succeeded",environment:{runner:"macos-15",channel:"production",workflow:"Build Portside Runtime"},toolchain:{sourcePolicy:"vendor-only",runtimePublication:"dual-bucket"},provenance:$provenance[0],sbom:$sbom[0],testResult:{sourceBuild:"passed",manifest:"passed",dualBucketReplication:"passed",cleanInstall:"not_verified"},sourceSnapshotIds:$sourceSnapshotIds}')"
api_post "/v1/admin/builds/register" "$build_payload" "$build_output"
build_id="$(json_id "$build_output")"

artifact_ids_file="$temp_dir/artifact-ids.json"
printf '%s\n' '[]' > "$artifact_ids_file"
for component in wrapper engine winetricks; do
    case "$component" in
        wrapper) snapshot_id="$wrapper_snapshot_id"; source_repository="https://github.com/andre-fig/portside"; source_commit="$portside_commit" ;;
        engine) snapshot_id="$wine_snapshot_id"; source_repository="$wine_repository"; source_commit="$wine_commit" ;;
        winetricks) snapshot_id="$winetricks_snapshot_id"; source_repository="$winetricks_repository"; source_commit="$winetricks_commit" ;;
    esac
    component_output="$temp_dir/artifact-$component.json"
    artifact_payload="$(jq -n \
        --arg component "$component" \
        --arg version "$manifest_version" \
        --arg sourceURL "$(jq -er --arg component "$component" '.components[] | select(.component == $component) | .downloadURL' "$manifest")" \
        --arg sourceRepository "$source_repository" \
        --arg sourceCommitOrTag "$source_commit" \
        --arg sourceSnapshotId "$snapshot_id" \
        --arg buildId "$build_id" \
        --arg license "$(jq -er --arg component "$component" '.components[] | select(.component == $component) | .license' "$manifest")" \
        --arg fileName "$(jq -er --arg component "$component" '.components[] | select(.component == $component) | .downloadURL | split("/") | last' "$manifest")" \
        --argjson size "$(jq -er --arg component "$component" '.components[] | select(.component == $component) | .size' "$manifest")" \
        --arg expectedSHA256 "$(jq -er --arg component "$component" '.components[] | select(.component == $component) | .sha256' "$manifest")" \
        --slurpfile provenance "$provenance" \
        --slurpfile sbom "$sbom" \
        '{component:$component,version:$version,sourceURL:$sourceURL,sourceRepository:$sourceRepository,sourceCommitOrTag:$sourceCommitOrTag,sourceSnapshotId:$sourceSnapshotId,buildId:$buildId,license:$license,fileName:$fileName,size:$size,expectedSHA256:$expectedSHA256,provenance:$provenance[0],sbom:$sbom[0]}')"
    api_post "/v1/admin/artifacts/register-published" "$artifact_payload" "$component_output"
    artifact_id="$(json_id "$component_output")"
    jq --arg id "$artifact_id" '. + [$id]' "$artifact_ids_file" > "$temp_dir/artifact-ids.next.json"
    mv "$temp_dir/artifact-ids.next.json" "$artifact_ids_file"
done

release_output="$temp_dir/release.json"
release_payload="$(jq -n \
    --arg version "$manifest_version" \
    --arg buildId "$build_id" \
    --arg manifestVersion "$manifest_version" \
    --arg manifestURL "$API_URL/v1/runtime/manifest" \
    --slurpfile artifactIds "$artifact_ids_file" \
    '{version:$version,channel:"production",buildId:$buildId,manifestVersion:$manifestVersion,manifestURL:$manifestURL,artifactIds:$artifactIds[0]}')"
api_post "/v1/admin/releases/register" "$release_payload" "$release_output"
release_id="$(json_id "$release_output")"

publish_output="$temp_dir/manifest.json"
publish_payload="$(jq -n --arg channel production --arg releaseId "$release_id" --slurpfile manifest "$manifest" '{channel:$channel,releaseId:$releaseId,manifest:$manifest[0]}')"
api_post "/v1/admin/manifests/publish" "$publish_payload" "$publish_output"
printf 'runtime_release_id=%s\n' "$release_id" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "Registered the production runtime build, artifacts, release and signed manifest."
