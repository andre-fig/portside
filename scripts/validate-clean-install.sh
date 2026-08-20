#!/bin/sh
set -eu

# Operator-assisted acceptance test for a real macOS GUI session. It refuses
# to infer graphical success from process existence, Dock state or a helper
# PID. It never captures screenshots or account data.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARTIFACTS_DIR="${PORTSIDE_RUNTIME_ARTIFACTS_DIR:?Set PORTSIDE_RUNTIME_ARTIFACTS_DIR to a downloaded workflow artifact}"
VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
TMP_BASE="${TMPDIR:-/tmp}"
CLEAN_ROOT="${PORTSIDE_CLEAN_ROOT:-$TMP_BASE/portside-clean-install-$VERSION}"
PREVIOUS_ARTIFACTS_DIR="${PORTSIDE_PREVIOUS_RUNTIME_ARTIFACTS_DIR:-}"
PREVIOUS_VERSION="${PORTSIDE_PREVIOUS_RUNTIME_VERSION:-}"
LOG_DIR="$CLEAN_ROOT/logs"
PREFIX="$CLEAN_ROOT/prefix"
CURRENT_WRAPPER="$CLEAN_ROOT/current/PortsideBaseline.app"

case "$VERSION" in
    ''|*[!A-Za-z0-9._-]*) echo "runtime version contains unsafe path characters" >&2; exit 1 ;;
esac
if [ -n "$PREVIOUS_VERSION" ]; then
    case "$PREVIOUS_VERSION" in
        *[!A-Za-z0-9._-]*) echo "previous runtime version contains unsafe path characters" >&2; exit 1 ;;
    esac
fi

case "$CLEAN_ROOT" in
    "$ROOT_DIR"/*|"$TMP_BASE"/*|/tmp/*|/private/tmp/*|"$HOME"/*) ;;
    *) echo "clean install root must be isolated from the checkout and user data" >&2; exit 1 ;;
esac
case "$ARTIFACTS_DIR" in
    "$ROOT_DIR"/*|"$TMP_BASE"/*|/tmp/*|/private/tmp/*|"$HOME"/*) ;;
    *) echo "runtime artifacts must come from a local workflow download" >&2; exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }
command -v open >/dev/null 2>&1 || { echo "open is required on macOS" >&2; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "perl is required to sanitize acceptance logs" >&2; exit 1; }
mkdir -p "$LOG_DIR"
umask 077

sanitize_file() {
    input="$1"
    output="$2"
    perl -pe '
        s#\Q$ENV{HOME}\E#\$USER_HOME#g;
        s#(?i)(password|passwd|token|cookie|sessionid|steamid|auth)([[:space:]]*[=:][[:space:]]*)[^[:space:],;]+#$1$2<redacted>#g;
        s#(?i)(-steamid|--steamid)[[:space:]]+[^[:space:]]+#$1 <redacted>#g;
    ' "$input" > "$output"
    rm -f "$input"
}

run_logged() {
    name="$1"
    shift
    raw="$LOG_DIR/$name.raw"
    clean="$LOG_DIR/$name.log"
    status=0
    ( "$@" ) >"$raw" 2>&1 || status=$?
    sanitize_file "$raw" "$clean"
    if [ "$status" -ne 0 ]; then
        echo "${name} failed with status ${status}; see ${clean}" >&2
        return "$status"
    fi
}

verify_manifest_and_artifacts() {
    source_dir="$1"
    source_version="$2"
    manifest="$source_dir/runtime-manifest.json"
    [ -s "$manifest" ] || { echo "signed runtime-manifest.json is missing in $source_dir" >&2; exit 1; }
    "$ROOT_DIR/scripts/build-runtime/validate-manifest.sh" "$manifest"
    jq -e --arg version "$source_version" '
      (.signature | strings | length > 0) and
      (.manifestVersion == $version) and
      (.channel | IN("staging", "production")) and
      (.components | length == 3)
    ' "$manifest" >/dev/null || {
        echo "clean acceptance requires a signed manifest matching version $source_version" >&2
        exit 1
    }
    for component in wrapper engine winetricks; do
        file_name="$(jq -r --arg component "$component" '.components[] | select(.component == $component) | .downloadURL | split("/") | last' "$manifest")"
        case "$file_name" in
            ''|.|..|*/*|*\\*) echo "manifest has an unsafe artifact filename" >&2; exit 1 ;;
        esac
        artifact="$source_dir/$file_name"
        expected_sha="$(jq -r --arg component "$component" '.components[] | select(.component == $component) | .sha256' "$manifest")"
        expected_size="$(jq -r --arg component "$component" '.components[] | select(.component == $component) | .size' "$manifest")"
        [ -s "$artifact" ] || { echo "missing $component artifact: $artifact" >&2; exit 1; }
        actual_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
        actual_size="$(wc -c < "$artifact" | tr -d '[:space:]')"
        [ "$actual_sha" = "$expected_sha" ] || { echo "$component checksum mismatch" >&2; exit 1; }
        [ "$actual_size" = "$expected_size" ] || { echo "$component size mismatch" >&2; exit 1; }
        case "$artifact" in *Sikarugir*|*Template*|*github*) echo "legacy artifact name in workflow output" >&2; exit 1 ;; esac
    done
}

materialize_wrapper() {
    source_dir="$1"
    source_version="$2"
    destination="$3"
    work="$CLEAN_ROOT/work-$source_version"
    rm -rf "$work" "$destination"
    mkdir -p "$work" "$destination"
    tar -xJf "$source_dir/PortsideWrapper-$source_version.tar.xz" -C "$destination"
    tar -xJf "$source_dir/PortsideWineEngine-$source_version.tar.xz" -C "$work"
    tar -xJf "$source_dir/PortsideWinetricks-$source_version.tar.xz" -C "$work"
    wrapper="$destination/PortsideBaseline.app"
    engine="$work/PortsideWineEngine-$source_version"
    winetricks="$work/PortsideWinetricks-$source_version"
    [ -x "$wrapper/Contents/MacOS/PortsideRuntimeHost" ] || { echo "wrapper host is missing" >&2; exit 1; }
    [ -x "$engine/bin/wine" ] && [ -x "$engine/bin/wineboot" ] && [ -x "$engine/bin/wineserver" ] && [ -d "$engine/share-wine" ] || { echo "Wine engine is incomplete" >&2; exit 1; }
    [ -x "$winetricks/src/winetricks" ] || { echo "winetricks is incomplete" >&2; exit 1; }
    mkdir -p "$wrapper/Contents/SharedSupport"
    cp -R "$engine" "$wrapper/Contents/SharedSupport/engine"
    mkdir -p "$wrapper/Contents/SharedSupport/engine/share"
    mv "$wrapper/Contents/SharedSupport/engine/share-wine" "$wrapper/Contents/SharedSupport/engine/share/wine"
    cp -R "$winetricks" "$wrapper/Contents/SharedSupport/winetricks"
    mkdir -p "$PREFIX"
    ln -s "$PREFIX" "$wrapper/Contents/SharedSupport/prefix"
    plutil -p "$wrapper/Contents/Info.plist" | grep -q '"PortsideRenderer" => "WineD3D"'
    ! plutil -p "$wrapper/Contents/Info.plist" | grep -Eqi 'D3DMetal.*=> 1|DXMT.*=> 1|DXVK.*=> 1'
}

processes_for_prefix() {
    ps -axo pid=,command= | awk -v prefix="$PREFIX" -v root="$CLEAN_ROOT" 'index($0, prefix) || index($0, root) {print $1}'
}

stop_prefix_processes() {
    for pid in $(processes_for_prefix); do
        case "$pid" in ''|1|"$$") continue ;; esac
        kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 2
    for pid in $(processes_for_prefix); do
        case "$pid" in ''|1|"$$") continue ;; esac
        kill -KILL "$pid" 2>/dev/null || true
    done
}

confirm() {
    prompt="$1"
    answer=""
    if [ ! -t 0 ]; then
        echo "No interactive terminal is attached. The GUI remains open for manual inspection; this run cannot claim acceptance." >&2
        trap - EXIT INT TERM
        exit 2
    fi
    printf '\n%s Type YES to record this manual check: ' "$prompt"
    IFS= read -r answer
    [ "$answer" = "YES" ] || { echo "manual check was not confirmed" >&2; exit 1; }
}

verify_manifest_and_artifacts "$ARTIFACTS_DIR" "$VERSION"
if [ -n "$PREVIOUS_ARTIFACTS_DIR" ]; then
    [ -n "$PREVIOUS_VERSION" ] || { echo "previous runtime version is required with previous artifacts" >&2; exit 1; }
    verify_manifest_and_artifacts "$PREVIOUS_ARTIFACTS_DIR" "$PREVIOUS_VERSION"
fi

trap 'stop_prefix_processes' EXIT INT TERM
rm -rf "$CLEAN_ROOT"
mkdir -p "$LOG_DIR" "$PREFIX"
materialize_wrapper "$ARTIFACTS_DIR" "$VERSION" "$CLEAN_ROOT/current"

echo "Creating a new isolated prefix at $PREFIX"
run_logged prefix-creation "$CURRENT_WRAPPER/Contents/MacOS/PortsideRuntimeHost" --create-prefix
echo "Installing Steam through the vendored winetricks steam verb"
run_logged steam-install "$CURRENT_WRAPPER/Contents/MacOS/PortsideRuntimeHost" --winetricks steam
[ -f "$PREFIX/drive_c/Program Files (x86)/Steam/steam.exe" ] || { echo "steam.exe was not installed by winetricks" >&2; exit 1; }

echo "Opening the first Steam execution. Wait for the updater to finish and for Steam to close once."
open "$CURRENT_WRAPPER"
confirm "Confirm the updater finished and this first Steam execution closed"

echo "Opening the wrapper a second time. Do not use a native macOS Steam session."
open "$CURRENT_WRAPPER"
confirm "Confirm PortsideBaseline appears in the Dock and a real Steam window is visible"
confirm "Confirm the login page is rendered and keyboard/mouse input works in its fields"
confirm "Confirm steamwebhelper remains running and Steam stays open after the updater"

printf 'validated at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PREFIX/PortsideValidation.marker"
if [ -n "$PREVIOUS_ARTIFACTS_DIR" ]; then
    stop_prefix_processes
    materialize_wrapper "$PREVIOUS_ARTIFACTS_DIR" "$PREVIOUS_VERSION" "$CLEAN_ROOT/previous"
    [ -f "$PREFIX/PortsideValidation.marker" ] || { echo "prefix data was lost during rollback preparation" >&2; exit 1; }
    echo "Opening the previous runtime with the same prefix to exercise rollback."
    open "$CLEAN_ROOT/previous/PortsideBaseline.app"
    confirm "Confirm the previous runtime opened with the same Steam data"
    stop_prefix_processes
    materialize_wrapper "$ARTIFACTS_DIR" "$VERSION" "$CLEAN_ROOT/current"
    [ -f "$PREFIX/PortsideValidation.marker" ] || { echo "prefix data was lost during update preparation" >&2; exit 1; }
    echo "Opening the candidate runtime again with the preserved prefix."
    open "$CURRENT_WRAPPER"
    confirm "Confirm the candidate runtime reopened with the preserved Steam data"
    echo "The same isolated prefix survived candidate/previous wrapper replacement."
fi

confirm "Confirm the free control game installed, launched and closed successfully (App ID 3139440)"
echo "Clean GUI acceptance confirmed by the operator. Sanitized logs: $LOG_DIR"
