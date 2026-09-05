# Compatibility engine

The compatibility layer inspects managed game files and records per-executable
profiles. It does not replace bootstrap, migrate native Steam data or establish
game playability. Main sources are [CompatibilityEngine.swift](../apps/desktop/Sources/PortsideCore/CompatibilityEngine.swift),
[RendererCompatibility.swift](../apps/desktop/Sources/PortsideCore/RendererCompatibility.swift)
and [PortsideAgent.swift](../apps/desktop/Sources/PortsideCore/PortsideAgent.swift).

## Implemented path and boundaries

1. `SteamLibraryScanner` parses Valve KeyValues within managed roots, correlates
   installed manifests and performs a bounded executable scan.
2. `PEImportScanner` reads headers/imports/strings without executing games.
   API, engine, launcher and anti-cheat matches are evidence, not compatibility proof.
3. `CompatibilityProfileProvider` can prioritize an injected backend-validated
   profile, then locally validated/user-confirmed data, PE analysis and default.
   The normal Agent has no remote provider, and the backend has no profile endpoint.
4. Renderer configuration records per-executable preferences/AppDefaults when
   invoked; restoring its stored snapshot does not prove complete registry recovery. It does not install missing renderer payloads or modify
   game binaries.
5. The Agent samples managed processes and stores technical outcomes. Automatic
   post-failure fallback policy exists, but no production retry orchestration is wired.

Inventory/registry code still uses `SharedSupport/wine` while current runtime
installation uses `SharedSupport/engine`; see [RENDERERS](RENDERERS.md).
Do not claim the intended profile path works end to end from unit fixtures.

The compatibility Agent exits with its managed Steam tree. Its separate
runtime-update-worker mode has another lifetime described in [ARCHITECTURE](ARCHITECTURE.md).
`PortsideAgent --capture-diagnostics` is an implemented diagnostic mode, not a
read-only repository audit command: it reads installed state and writes an export.

Profiles/attempts may contain executable paths. Logs and exports have different
sanitization boundaries; review [SECURITY](SECURITY.md) before sharing.
