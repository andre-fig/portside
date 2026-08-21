# Portside architecture

## Runtime boundary

PortsideCore owns the Sikarugir lifecycle:

- PortsidePaths keeps wrappers, prefixes, SteamLibrary, caches, logs,
  diagnostics, profiles and manifests in separate user-local directories.
- SikarugirOfficialCatalog pins official HTTPS release/source URLs, SHA-256
  values, sizes and source commits for Creator provenance, Wrapper template,
  Engines and Sikarugir winetricks.
- SikarugirUpdateService validates the pinned catalog, caches verified
  downloads, checks the official EngineList.txt at most once per day and
  supports offline reuse of verified artifacts.
- SikarugirWrapperInstaller extracts archives with direct /usr/bin/tar
  arguments after validating every archive path, installs side-by-side, writes
  the wrapper Info.plist, and leaves the previous wrapper in a rollback
  location.
- SikarugirSteamFlow exposes exactly two process specifications:
  WSS-winetricks steam for installation and a clean wrapper launch. It never
  invokes SteamSetup.exe, native macOS Steam, a shell, or the old login flags.
- SteamReadinessMonitor observes managed process arguments and macOS on-screen
  window metadata only. It never captures pixels or window content. Its
  strongest automatic state is visibleButUnverified; manual visual
  confirmation is required before recording uiReady.
- GameCompatibilityService detects PE architecture/API, chooses mutually
  exclusive official renderer profiles, and keeps a bounded fallback path for
  unknown games.

The SwiftUI target owns only the minimal preparation window. Once a managed
Steam window exists, Portside hides and exits. Creator and Configure are not
opened or copied into the Portside application bundle.

## Golden baseline configuration

~~~text
Wrapper template  1.0.11
Engine            WS12WineSikarugir10.0_6
Renderer          WineD3D
D3DMETAL         0
DXMT             0
DXVK             0
WINEMSYNC        1
WINEESYNC        1
WINEDEBUG        -plugplay,+loaddll
Program Flags    empty
~~~

The engine archive and template are verified before extraction. Prefix
creation and Steam installation stay inside the wrapper’s official
Contents/SharedSupport/prefix. A small metadata record in Prefixes points to
that canonical prefix; the prefix is not duplicated.

## Update and rollback

Updates are downloaded to Cache/Downloads, verified, extracted to a unique
temporary directory and activated atomically. The previous wrapper is retained
under Runtime/rollback-*. A candidate must pass structure and engine
validation before activation; a failed Steam-window smoke test keeps the
previous active wrapper. SteamLibrary and saves are never rollback targets.

## Diagnostics and security

Sentry receives only the allow-listed fields documented in DiagnosticContext:
Sikarugir/template/engine versions, renderer, App ID, architecture/API,
attempt/fallback indexes, exit code, window state and rollback state.
Passwords, cookies, tokens, Steam IDs, account data, window content,
screenshots and full user paths are sanitized or omitted.

Process launches use Process with fixed executable URLs and argument arrays.
Managed termination requires the wrapper/prefix path in the process command, so
native Steam and unrelated Wine wrappers are not killed.

The Portside wrapper removes the upstream template's generic
`NSMicrophoneUsageDescription`. Portside has no microphone capture path and
does not request microphone permission; Steam voice input, if desired later,
would require an explicit separate feature and permission decision.
