#!/bin/sh
# Build the pinned font library for the Wine target, independently of Homebrew's
# host architecture. No compiled upstream runtime is downloaded.
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD_DIR="${PORTSIDE_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/runtime}"
case "$BUILD_DIR" in "$ROOT_DIR"/*) ;; *) echo "build directory must be inside the checkout" >&2; exit 1 ;; esac
dependency="$(jq -c '.dependencies[] | select(.name == "freetype")' "$ROOT_DIR/upstream/dependencies.json")"
version="$(printf '%s' "$dependency" | jq -r '.version')"
url="$(printf '%s' "$dependency" | jq -r '.origin')"
checksum="$(printf '%s' "$dependency" | jq -r '.sha256')"
case "$version" in ''|*[!0-9.]*) echo "invalid FreeType version" >&2; exit 1 ;; esac
WORK="$BUILD_DIR/work/freetype"
mkdir -p "$WORK"
archive="$WORK/source.tar.xz"
if [ ! -f "$archive" ] || [ "$(shasum -a 256 "$archive" | awk '{print $1}')" != "$checksum" ]; then
    curl --fail --location --proto '=https' --proto-redir '=https' --output "$archive" "$url"
fi
[ "$(shasum -a 256 "$archive" | awk '{print $1}')" = "$checksum" ] || { echo "FreeType checksum mismatch" >&2; exit 1; }
rm -rf "$WORK/source" "$WORK/install"
mkdir -p "$WORK/source" "$WORK/install"
tar -xJf "$archive" -C "$WORK/source" --strip-components=1
cd "$WORK/source"
# FreeType includes its own gzip inflater. Keep the rasterizer self-contained;
# optional PNG, Brotli, bzip2 and HarfBuzz integrations are not runtime inputs.
CC=clang CFLAGS='-O2 -arch x86_64' LDFLAGS='-arch x86_64' \
    ./configure --host=x86_64-apple-darwin --prefix="$WORK/install" \
    --disable-static --enable-shared --without-zlib --without-bzip2 \
    --without-png --without-harfbuzz --without-brotli
make -j"${PORTSIDE_BUILD_JOBS:-8}"
make install
[ "$(lipo -archs "$WORK/install/lib/libfreetype.6.dylib")" = x86_64 ] || { echo "FreeType target mismatch" >&2; exit 1; }
mkdir -p "$WORK/install/licenses"
cp docs/FTL.TXT LICENSE.TXT "$WORK/install/licenses/"
