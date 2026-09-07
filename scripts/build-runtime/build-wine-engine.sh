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
# This source tree's Darwin loader uses a low-address, 4 KiB layout. It is
# not an arm64 macOS CPU-emulation backend for Windows x86 Steam. Build the
# Unix engine for x86_64 (Rosetta on Apple silicon); native build tools stay native.
target_arch="${PORTSIDE_WINE_ARCH:-x86_64}"
# Match the app/wrapper contract independently of the developer's installed SDK.
export MACOSX_DEPLOYMENT_TARGET=13.0
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
cross_cflags="${CROSSCFLAGS:--g -O2}"

case "$native_arch:$target_arch" in
    x86_64:x86_64|arm64:x86_64) ;;
    *) echo "unsupported Portside Wine architecture pair: $native_arch -> $target_arch" >&2; exit 1 ;;
esac

wine_snapshot_checksum="$(jq -r '.repositories[] | select(.name == "wine") | .snapshotChecksum' "$ROOT_DIR/upstream/lock.json")"
macos_version="$(sw_vers -productVersion 2>/dev/null || uname -s)"
xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ';' || true)"
clang_version="$(clang --version | head -n 1)"
recipe_checksum="$(cat "$0" "$ROOT_DIR/scripts/build-runtime/build-freetype.sh" "$ROOT_DIR/upstream/dependencies.json" | shasum -a 256 | awk '{print $1}')"
cache_signature="$recipe_checksum|$wine_version|$wine_snapshot_checksum|$native_arch|$target_arch|$MACOSX_DEPLOYMENT_TARGET|$native_cflags|$native_cxxflags|$native_ldflags|$target_cflags|$target_cxxflags|$target_ldflags|$cross_cflags|$macos_version|$xcode_version|$clang_version"
# Keep developer checkout paths out of native/PE debug data and __FILE__.
# The virtual destination is stable; the disposable source directory is not a
# cache input because its actual location must not affect the resulting bytes.
prefix_maps="-ffile-prefix-map=$ROOT_DIR=/portside-source -fdebug-prefix-map=$ROOT_DIR=/portside-source"

package_engine() {
    ENGINE_STAGE="$WORK_DIR/PortsideWineEngine-$VERSION"
    mkdir -p "$ENGINE_STAGE"
    cp -R "$INSTALL_ROOT/bin" "$ENGINE_STAGE/"
    cp -R "$INSTALL_ROOT/lib" "$ENGINE_STAGE/"
    cp -R "$INSTALL_ROOT/share/wine" "$ENGINE_STAGE/share-wine"
    "$ROOT_DIR/scripts/build-runtime/validate-engine-execution.py" "$INSTALL_ROOT"
    python3 "$ROOT_DIR/scripts/build-runtime/validate-engine-privacy.py" "$ENGINE_STAGE"
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
export CFLAGS="$native_cflags ${FREETYPE_CPPFLAGS:-} $prefix_maps"
export CXXFLAGS="$native_cxxflags ${FREETYPE_CPPFLAGS:-} $prefix_maps"
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
"$ROOT_DIR/scripts/build-runtime/build-freetype.sh"
target_freetype="$BUILD_DIR/work/freetype/install"
export FREETYPE_CFLAGS="-I$target_freetype/include/freetype2"
export FREETYPE_LIBS="-L$target_freetype/lib -lfreetype"
export CFLAGS="$target_cflags $prefix_maps"
export CXXFLAGS="$target_cxxflags $prefix_maps"
export LDFLAGS="$target_ldflags"
export CROSSCFLAGS="$cross_cflags $prefix_maps"
"$SOURCE_COPY/configure" \
    --build="$(uname -m)-apple-darwin" \
    --host="$host" \
    --prefix=/opt/portside-wine \
    --with-wine-tools="$TOOLS_TREE" \
    --enable-win64 \
    --enable-archs=i386,x86_64 \
    --disable-tests
make -j"$jobs"
make install DESTDIR="$WORK_DIR/dest"
rmdir "$INSTALL_ROOT"
mv "$WORK_DIR/dest/opt/portside-wine" "$INSTALL_ROOT"
cp -L "$target_freetype/lib/libfreetype.6.dylib" "$INSTALL_ROOT/lib/wine/x86_64-unix/"
install_name_tool -id '@rpath/libfreetype.6.dylib' "$INSTALL_ROOT/lib/wine/x86_64-unix/libfreetype.6.dylib"
mkdir -p "$INSTALL_ROOT/share/wine/licenses/freetype"
cp "$target_freetype/licenses/"* "$INSTALL_ROOT/share/wine/licenses/freetype/"

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
