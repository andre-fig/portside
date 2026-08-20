#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
VERSION="${PORTSIDE_RUNTIME_VERSION:?Set PORTSIDE_RUNTIME_VERSION}"
SOURCE_DIR="$ROOT_DIR/vendor/wine"
WORK_DIR="$BUILD_DIR/work/wine"
SOURCE_COPY="$WORK_DIR/source"
BUILD_TREE="$WORK_DIR/build"
TOOLS_TREE="$WORK_DIR/tools"
INSTALL_ROOT="$WORK_DIR/install"
ARCHIVE="$BUILD_DIR/PortsideWineEngine-$VERSION.tar.xz"
CACHE_ROOT="${PORTSIDE_WINE_CACHE_DIR:-$ROOT_DIR/.cache/portside-wine}"

"$ROOT_DIR/scripts/upstream/validate_snapshot.sh" "$SOURCE_DIR"
[ -f "$SOURCE_DIR/configure.ac" ] || { echo "vendor/wine/configure.ac is missing" >&2; exit 1; }
[ -f "$SOURCE_DIR/VERSION" ] || { echo "vendor/wine/VERSION is missing" >&2; exit 1; }
case "$BUILD_DIR" in "$ROOT_DIR"/*) ;; *) echo "runtime build directory must be inside the checkout" >&2; exit 1 ;; esac
case "$(uname -s)" in Darwin) ;; *) echo "the Portside Wine engine recipe requires a macOS runner" >&2; exit 1 ;; esac

if command -v brew >/dev/null 2>&1; then
    bison_prefix="$(brew --prefix bison 2>/dev/null || true)"
    flex_prefix="$(brew --prefix flex 2>/dev/null || true)"
    mingw_prefix="$(brew --prefix mingw-w64 2>/dev/null || true)"
    llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
    lld_prefix="$(brew --prefix lld 2>/dev/null || true)"
    freetype_prefix="$(brew --prefix freetype 2>/dev/null || true)"
    pkgconfig_prefix="$(brew --prefix pkgconf 2>/dev/null || true)"
    [ -x "$bison_prefix/bin/bison" ] && PATH="$bison_prefix/bin:$PATH"
    [ -x "$flex_prefix/bin/flex" ] && PATH="$flex_prefix/bin:$PATH"
    [ -d "$mingw_prefix/bin" ] && PATH="$mingw_prefix/bin:$PATH"
    [ -d "$llvm_prefix/bin" ] && PATH="$llvm_prefix/bin:$PATH"
    [ -d "$lld_prefix/bin" ] && PATH="$lld_prefix/bin:$PATH"
    [ -d "$pkgconfig_prefix/bin" ] && PATH="$pkgconfig_prefix/bin:$PATH"
    if [ -n "$freetype_prefix" ] && [ -d "$freetype_prefix/lib/pkgconfig" ]; then
        PKG_CONFIG_PATH="$freetype_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        export PKG_CONFIG_PATH
    fi
    if [ -n "$freetype_prefix" ] && [ -d "$freetype_prefix/include" ] && [ -d "$freetype_prefix/lib" ]; then
        FREETYPE_CPPFLAGS="-I$freetype_prefix/include/freetype2"
        FREETYPE_LDFLAGS="-L$freetype_prefix/lib"
        export FREETYPE_CPPFLAGS FREETYPE_LDFLAGS
    fi
    export PATH
fi

for tool in clang clang++ make tar shasum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required for the Portside Wine build" >&2; exit 1; }
done

native_arch="$(uname -m)"
target_arch="${PORTSIDE_WINE_ARCH:-$native_arch}"
jobs="${PORTSIDE_BUILD_JOBS:-$(sysctl -n hw.ncpu)}"
wine_version="$(tr -d '[:space:]' < "$SOURCE_DIR/VERSION")"
host="${target_arch}-apple-darwin"
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"
native_cflags="${PORTSIDE_WINE_NATIVE_CFLAGS:--O2 -arch $native_arch}"
native_cxxflags="${PORTSIDE_WINE_NATIVE_CXXFLAGS:--O2 -arch $native_arch}"
native_ldflags="${PORTSIDE_WINE_NATIVE_LDFLAGS:--arch $native_arch}"
target_cflags="${PORTSIDE_WINE_CFLAGS:--O2 -arch $target_arch}"
target_cxxflags="${PORTSIDE_WINE_CXXFLAGS:--O2 -arch $target_arch}"
target_ldflags="${PORTSIDE_WINE_LDFLAGS:--arch $target_arch}"

case "$native_arch:$target_arch" in
    arm64:arm64|x86_64:x86_64|arm64:x86_64) ;;
    *) echo "unsupported Portside Wine architecture pair: $native_arch -> $target_arch" >&2; exit 1 ;;
esac

wine_snapshot_checksum="$(jq -r '.repositories[] | select(.name == "wine") | .snapshotChecksum' "$ROOT_DIR/upstream/lock.json")"
macos_version="$(sw_vers -productVersion 2>/dev/null || uname -s)"
xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ';' || true)"
clang_version="$(clang --version | head -n 1)"
cache_signature="$wine_version|$wine_snapshot_checksum|$native_arch|$target_arch|$native_cflags|$native_cxxflags|$native_ldflags|$target_cflags|$target_cxxflags|$target_ldflags|$macos_version|$xcode_version|$clang_version"

package_engine() {
    ENGINE_STAGE="$WORK_DIR/PortsideWineEngine-$VERSION"
    mkdir -p "$ENGINE_STAGE"
    cp -R "$INSTALL_ROOT/bin" "$ENGINE_STAGE/"
    cp -R "$INSTALL_ROOT/lib" "$ENGINE_STAGE/"
    cp -R "$INSTALL_ROOT/share/wine" "$ENGINE_STAGE/share-wine"
    printf 'Wine %s\nPortside build target: %s\nWoW64 PE architectures: i386,x86_64\n' "$wine_version" "$target_arch" > "$ENGINE_STAGE/version"
    rm -f "$ARCHIVE"
    "$ROOT_DIR/scripts/build-runtime/create-archive.sh" "$ARCHIVE" "$WORK_DIR" "PortsideWineEngine-$VERSION"
    shasum -a 256 "$ARCHIVE" | awk '{print $1 "  " $2}' > "$BUILD_DIR/PortsideWineEngine-$VERSION.sha256"
}

force_rebuild="${PORTSIDE_WINE_FORCE_REBUILD:-false}"
if [ "$force_rebuild" != "1" ] && [ "$force_rebuild" != "true" ] && [ "$(cat "$CACHE_ROOT/metadata" 2>/dev/null || true)" = "$cache_signature" ] && [ -x "$CACHE_ROOT/install/bin/wine" ] && [ -x "$CACHE_ROOT/install/bin/wineserver" ] && [ -x "$CACHE_ROOT/install/bin/wineboot" ] && [ -d "$CACHE_ROOT/install/share/wine" ]; then
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    INSTALL_ROOT="$CACHE_ROOT/install"
    package_engine
    echo "Reused cached Wine engine for $wine_version ($target_arch)."
    exit 0
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$BUILD_TREE" "$TOOLS_TREE" "$INSTALL_ROOT"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude .git "$SOURCE_DIR/" "$SOURCE_COPY/"
else
    cp -R "$SOURCE_DIR" "$SOURCE_COPY"
fi

# The native tools are executed by the build machine. They must use the
# machine architecture even when a separate target architecture is selected.
export CFLAGS="$native_cflags ${FREETYPE_CPPFLAGS:-}"
export CXXFLAGS="$native_cxxflags ${FREETYPE_CPPFLAGS:-}"
export LDFLAGS="$native_ldflags ${FREETYPE_LDFLAGS:-}"

cd "$TOOLS_TREE"
"$SOURCE_COPY/configure" \
    --build="$(uname -m)-apple-darwin" \
    --host="$(uname -m)-apple-darwin" \
    --prefix="$TOOLS_TREE/install" \
    --disable-tests \
    --enable-archs=none \
    --without-x
mkdir -p "$TOOLS_TREE/nls"
cp -R "$SOURCE_COPY/nls/." "$TOOLS_TREE/nls/"
make -j"$jobs" \
    tools/install \
    tools/makedep \
    tools/make_xftmpl \
    tools/sfnt2fon/sfnt2fon \
    tools/winebuild/winebuild \
    tools/winegcc/winegcc \
    tools/widl/widl \
    tools/wmc/wmc \
    tools/wrc/wrc

rm -rf "$BUILD_TREE"
mkdir -p "$BUILD_TREE"
cd "$BUILD_TREE"
export CFLAGS="$target_cflags ${FREETYPE_CPPFLAGS:-}"
export CXXFLAGS="$target_cxxflags ${FREETYPE_CPPFLAGS:-}"
export LDFLAGS="$target_ldflags ${FREETYPE_LDFLAGS:-}"
"$SOURCE_COPY/configure" \
    --build="$(uname -m)-apple-darwin" \
    --host="$host" \
    --prefix="$INSTALL_ROOT" \
    --with-wine-tools="$TOOLS_TREE" \
    --enable-win64 \
    --enable-archs=i386,x86_64 \
    --disable-tests
make -j"$jobs"
make install

[ -x "$INSTALL_ROOT/bin/wine" ] || { echo "Wine build did not produce bin/wine" >&2; exit 1; }
[ -x "$INSTALL_ROOT/bin/wineserver" ] || { echo "Wine build did not produce bin/wineserver" >&2; exit 1; }
[ -x "$INSTALL_ROOT/bin/wineboot" ] || { echo "Wine build did not produce bin/wineboot" >&2; exit 1; }
[ -d "$INSTALL_ROOT/share/wine" ] || { echo "Wine build did not produce share/wine" >&2; exit 1; }

mkdir -p "$CACHE_ROOT"
rm -rf "$CACHE_ROOT/install"
cp -R "$INSTALL_ROOT" "$CACHE_ROOT/install"
printf '%s' "$cache_signature" > "$CACHE_ROOT/metadata"
package_engine
echo "Built $ARCHIVE from vendor/wine $wine_version; no compiled upstream artifact was used."
