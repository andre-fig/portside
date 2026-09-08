# Portside Wine patches

This series applies to the Wine commit named in `series.json`, after the vendor
snapshot has been verified and copied to the disposable build tree. It never
changes `vendor/wine`. The manifest pins every patch's SHA-256; unknown, altered,
duplicate or nonapplicable patches fail the build. The recipe, application tool,
manifest and patch bytes participate in both install-cache and engine identities.
Git whitespace attributes allow unified-diff blank context markers in these
patch files. Patch checksums and clean application remain mandatory.

`0001-renderer-overlay-search.patch` is a Portside-authored LGPL-2.1-or-later
change to Wine's `set_dll_path`. It implements the `WINEDLLPATH_PREPEND` contract
used by the inspected Sikarugir launcher to select its renderer directories.
Nonempty absolute entries are searched in order before Wine's own DLL directory;
ordinary `WINEDLLPATH` follows it. Empty/relative overlay entries are ignored.
Unset/empty input preserves Wine's default order. No registry or prefix DLL is
rewritten and no Steam/CEF security or command-line workaround is included.

The launcher and old engine contain this variable, while the pinned Wine source
does not. A disposable Template 1.0.11/Portside-engine control with `DXMT=1`
continued loading Wine's own `d3d11.dll`/`dxgi.dll`, motivating this change.
This patch is not a claim to reproduce the complete upstream engine recipe.
Native function tests and a full local rebuild verify search ordering. The
[graphical control](../../../docs/SIKARUGIR_OVERLAY_VALIDATION.md) then loaded
DXMT, exposed its missing bridge dependency and cross-process presentation
restriction, and still displayed a black Steam window. This is a verified loader
contract correction, not an accepted graphical fix. Patch inventory is retained
in engine/runtime provenance and the Wine SPDX source information.
