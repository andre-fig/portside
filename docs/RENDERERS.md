# Renderer management

The [renderer implementation](../apps/desktop/Sources/PortsideCore/RendererCompatibility.swift)
represents WineD3D, DXMT, DXVK, VKD3D, native Vulkan and native OpenGL.
D3DMetal/GPTK is excluded as a selection option. Candidate enums do not imply
packaged or working capabilities; the [Portside baseline](RUNTIME.md) selects
WineD3D with alternate flags disabled.

`RuntimeComponentInventory` detects paths, versions and representative checksums.
`RendererManager.verify` checks the captured profile's availability; it does
not rehash the payload at every application. `install` only delegates to that
availability check. Current inventory/registry paths expect
`Contents/SharedSupport/wine`, unlike the installed `SharedSupport/engine`.

The manager persists configuration by App ID/executable and can write Wine
AppDefaults and restore stored configuration snapshots when invoked.
Tests disable registry writes; the current registry writer does not remove all
previous named overrides on rollback, so stored-state restoration does not prove
restored Wine registry behavior.
It does not download renderers, replace prefix-wide DLLs, modify game files
or copy saves. Per-executable fixture tests are not proof of isolation in every
shared prefix or game process.

`CompatibilityFallbackPolicy` allows one retry after graphics initialization
or shader failure, only offline, without anti-cheat evidence or a risk flag.
The helper can restore configuration before trying another candidate, but no
production post-failure retry orchestration invokes it end to end.

Use [GAME_PROFILES](GAME_PROFILES.md) for candidate ordering,
[COMPATIBILITY_LIMITATIONS](COMPATIBILITY_LIMITATIONS.md) for interpretation and
[TESTING](TESTING.md) for required code/manual checks. Do not carry historical
machine-specific renderer inventories into new release claims.
