# Portside architecture

## Boundaries

`PortsideCore` contains orchestration and persistence:

- `SystemRequirements` validates Apple silicon and free storage.
- `EnvironmentStore` owns `~/Library/Application Support/Portside` and creates `Runtime`, `Prefix/Steam`, `Logs`, `Cache`, `Downloads`, and `Diagnostics`. An older `Prefixes/Steam` directory is migrated in place without deleting its contents.
- `SecureDownloader` accepts HTTPS URLs only, downloads to a private destination, and records SHA-256.
- `SteamInstaller` owns the Valve installer URL and invokes it only through a discovered runtime, never through a shell.
- `FreeWineRuntimeProvider` is the concrete provider: pinned Wine 11.15, SHA-256 verification, resumable download, safe tar extraction, user-local GStreamer extraction, Rosetta detection, idempotent prefix initialization, and runtime record persistence.
- `RosettaManager` validates and requests Apple’s official Rosetta installation automatically when required; any protected macOS confirmation remains owned by macOS.
- `SteamReadinessMonitor` combines process snapshots with public CoreGraphics window inspection; a started process is not treated as a ready Steam session.
- `SteamHostLauncher` creates an idempotent private `~/Library/Application Support/Portside/Launchers/Steam.app` with the Portside-owned `com.portside.steam-launcher` identity and opens it through `NSWorkspace`. The native host supervises the Wine/Steam process tree, activates the Steam window when its Dock item is reopened, and exits after the managed Steam prefix stops.
- `ProcessSupervisor` remains responsible for silent bootstrap and scoped Wine shutdown; the visible Steam session is delegated to the dedicated host bundle.
- `WinePrefixManager` writes `ShowCrashDialog=0` to the Portside prefix and applies a `winedbg.exe=d` process policy. Supervisor shutdown targets only the Portside prefix through its exact `wineserver` path. The shared runtime `Info.plist` is never renamed to Steam; only the dedicated Steam launcher carries that user-facing identity.
- `DiagnosticsService` is the domain boundary for invisible Sentry monitoring, stable error codes, high-level breadcrumbs, and manual sanitized reports. The SDK adapter is isolated in the app target.
- `DiagnosticReport` writes a compact sanitized report without credentials or tokens.

The SwiftUI target owns the single automatic progress/failure window. It has no onboarding, dashboard, settings, or consent screen. The Steam UI remains the Steam client. DXMT is not installed because its current upstream repository reports no asserted license; WineD3D, which ships with Wine, is used for Direct3D 9/10/11.

## Security decisions

All remote downloads are HTTPS and the installer host is fixed. Process launch uses `Process` with a fixed array of arguments and a controlled environment. All diagnostic/log output is sanitized. Portside never asks for a Steam password and never writes credentials.

## Lifecycle

1. Load persisted state and automatically choose direct launch or resumable setup.
2. Validate machine and storage.
3. Create the private workspace.
4. Verify/install GStreamer locally and download Wine 11.15.
5. Verify and extract the runtime atomically.
6. Initialize the Steam prefix with `wineboot` through `Process`.
7. Download `SteamSetup.exe`.
8. Install Steam into the Portside Steam prefix with `/S` through the injected process runner.
9. Verify `steam.exe` exists and is executable.
10. Bootstrap Steam with `-silent` and wait for the installed-client marker.
11. Rebuild/validate the private `Steam.app` launcher if needed.
12. Open the launcher through LaunchServices with separated arguments.
13. The launcher starts Steam normally and waits for its window.

No process-start event is treated as a compatibility result. Actual game classifications require a real test report. Release Sentry uses no default PII, no user object, no replay, no network breadcrumbs, and no tracing sample by default; optional dSYM upload occurs only outside the app when `SENTRY_AUTH_TOKEN` is supplied to the packaging environment.
