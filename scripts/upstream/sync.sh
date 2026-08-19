#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
LOCK_FILE="$ROOT_DIR/upstream/lock.json"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/portside-upstream-sync.XXXXXX")"
changed=0

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[ -f "$LOCK_FILE" ] || { echo "missing $LOCK_FILE" >&2; exit 1; }
jq -e '.schemaVersion == 2 and (.repositories | type == "array")' "$LOCK_FILE" >/dev/null

mkdir -p "$TEMP_ROOT/staged/vendor" "$TEMP_ROOT/old"
cp "$LOCK_FILE" "$TEMP_ROOT/lock.json"
jq -r '.repositories[] | select(.sync == true) | [.name, .repository, .localPath] | @tsv' "$LOCK_FILE" > "$TEMP_ROOT/repositories.tsv"

while IFS=$(printf '\t') read -r name repository local_path; do
    [ -n "$name" ] || continue
    case "$local_path" in
        vendor/*) ;;
        *) echo "refusing non-vendor source path: $local_path" >&2; exit 1 ;;
    esac

    work="$TEMP_ROOT/source-$name"
    clone_options="--depth 1 --no-tags"
    if [ "$name" = "wine" ]; then
        clone_options="$clone_options --filter=blob:none"
    fi
    # shellcheck disable=SC2086
    git clone --quiet $clone_options "$repository.git" "$work"
    remote_commit=$(git -C "$work" rev-parse HEAD)
    locked_commit=$(jq -r --arg name "$name" '.repositories[] | select(.name == $name) | .commit' "$LOCK_FILE")
    if [ "$remote_commit" = "$locked_commit" ]; then
        echo "$name unchanged at $remote_commit"
        continue
    fi

    echo "$name changed: $locked_commit -> $remote_commit"
    changed=1
    if [ "${PORTSIDE_UPSTREAM_SYNC_DRY_RUN:-0}" = "1" ]; then
        continue
    fi
    git -C "$work" submodule update --init --recursive
    if [ -f "$work/.gitattributes" ] && grep -q 'filter=lfs' "$work/.gitattributes"; then
        command -v git-lfs >/dev/null 2>&1 || { echo "git-lfs is required for $name" >&2; exit 1; }
        git -C "$work" lfs pull
    fi

    staged="$TEMP_ROOT/staged/$local_path"
    mkdir -p "$staged"
    git -C "$work" archive --format=tar HEAD | tar -xf - -C "$staged"
    jq -r --arg name "$name" '.repositories[] | select(.name == $name) | .excludedPaths[]?' "$LOCK_FILE" > "$TEMP_ROOT/exclusions.txt"
    while IFS= read -r excluded; do
        [ -n "$excluded" ] || continue
        excluded_path="$staged/$excluded"
        case "$excluded_path" in
            "$staged"/*) ;;
            *) echo "invalid exclusion path for $name: $excluded" >&2; exit 1 ;;
        esac
        if [ -e "$excluded_path" ]; then
            rm -rf "$excluded_path"
        fi
    done < "$TEMP_ROOT/exclusions.txt"
    "$ROOT_DIR/scripts/upstream/validate_snapshot.sh" "$staged"
    checksum=$("$ROOT_DIR/scripts/upstream/snapshot_checksum.sh" "$staged")
    license_checksum=$("$ROOT_DIR/scripts/upstream/license_inventory_checksum.sh" "$staged")
    locked_license_checksum=$(jq -r --arg name "$name" '.repositories[] | select(.name == $name) | (.licenseSnapshotChecksum // "")' "$LOCK_FILE")
    license_changed=0
    if [ -n "$locked_license_checksum" ] && [ "$locked_license_checksum" != "$license_checksum" ]; then
        license_changed=1
        echo "LICENSE_CHANGE_DETECTED $name: $locked_license_checksum -> $license_checksum" >&2
    fi
    commit_date=$(git -C "$work" show -s --format=%cI HEAD)
    jq --arg name "$name" --arg commit "$remote_commit" --arg date "$commit_date" --arg checksum "$checksum" --arg licenseChecksum "$license_checksum" --argjson licenseChanged "$license_changed" '
      (.repositories[] | select(.name == $name)) |= (.commit = $commit | .commitDate = $date | .snapshotChecksum = $checksum | .licenseSnapshotChecksum = $licenseChecksum | .licenseChangeDetected = ($licenseChanged == 1) | .lastValidatedBuild = null)
      | .generatedAt = (now | strftime("%Y-%m-%d"))
    ' "$TEMP_ROOT/lock.json" > "$TEMP_ROOT/lock.next.json"
    mv "$TEMP_ROOT/lock.next.json" "$TEMP_ROOT/lock.json"
done < "$TEMP_ROOT/repositories.tsv"

if [ "$changed" -eq 0 ]; then
    echo "No upstream source changes detected."
    exit 0
fi

if jq -e '[.repositories[] | select(.licenseChangeDetected == true)] | length > 0' "$TEMP_ROOT/lock.json" >/dev/null; then
    echo "A license/notice change was detected. The source snapshot is not replaced; review and update the lockfile explicitly." >&2
    exit 2
fi

jq -r '.repositories[] | select(.sync == true) | [.name, .localPath] | @tsv' "$TEMP_ROOT/lock.json" > "$TEMP_ROOT/updated.tsv"
while IFS=$(printf '\t') read -r name local_path; do
    [ -n "$name" ] || continue
    staged="$TEMP_ROOT/staged/$local_path"
    [ -d "$staged" ] || continue
    current="$ROOT_DIR/$local_path"
    backup="$TEMP_ROOT/old/$name"
    if [ -d "$current" ]; then
        mv "$current" "$backup"
    fi
    mkdir -p "$(dirname "$current")"
    mv "$staged" "$current"
done < "$TEMP_ROOT/updated.tsv"

mv "$TEMP_ROOT/lock.json" "$LOCK_FILE"
echo "Upstream snapshots updated; review the generated diff before merging."
