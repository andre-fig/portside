# Portside architecture

## Boundaries

`PortsideCore` contains orchestration and persistence:

- `SystemRequirements` validates Apple silicon and free storage.
- `EnvironmentStore` owns `~/Library/Application Support/Portside` and creates `Runtime`, `Prefix/Steam`, `Logs`, `Cache`, `Downloads`, and `Diagnostics`. An older `Prefixes/Steam` directory is migrated in place without deleting its contents.
- `SecureDownloader` accepts HTTPS URLs only, downloads to a private destination, and records SHA-256.
- `SteamInstaller` owns the Valve installer URL and invokes it only through a discovered runtime, never through a shell.
- `SteamLaunchProfile` centralizes the post-install login arguments and keeps them separate from installer/bootstrap arguments; `SteamHostMain` passes them to the Windows `steam.exe` child through `Process.arguments`.
- `FreeWineRuntimeProvider` is the concrete provider: pinned Wine 11.15, SHA-256 verification, resumable download, safe tar extraction, user-local GStreamer extraction, Rosetta detection, idempotent prefix initialization, and runtime record persistence.
- `RosettaManager` validates and requests Apple’s official Rosetta installation automatically when required; any protected macOS confirmation remains owned by macOS.
- `SteamReadinessMonitor` combines process snapshots with public CoreGraphics window inspection; a started process, an activation request, or an existing black window is not treated as a ready Steam session.
- `SteamHostLauncher` maintains a private dedicated `Steam.app` with Steam bundle identity and starts the child with separated arguments and the inherited Wine environment. A POSIX launch lock prevents concurrent Portside instances from creating duplicate Steam trees, and the monitor force-terminates only Steam processes associated with the managed prefix when a strategy is replaced or setup fails.
- `ProcessSupervisor` remains responsible for silent bootstrap. The dedicated Steam host supervises the normal launch, while readiness remains the monitor's responsibility. Shutdown first requests `wineserver -k`, then terminates any remaining Steam command tree so no orphaned `steamwebhelper` processes remain.
- `WinePrefixManager` writes `ShowCrashDialog=0` to the Portside prefix and applies a `winedbg.exe=d` process policy. The shared runtime `Info.plist` is never renamed to Steam; the only visible Steam identity is the Wine-hosted process.
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
11. Ensure the private dedicated `Steam.app` host and validate its Steam identity.
12. Acquire the Portside launch lock and start exactly one Wine-hosted Steam process with separated arguments and the inherited environment.
13. Inspect the Steam window pixels, try the controlled CEF fallbacks when necessary, and wait for verified UI readiness before handing off and closing Portside.

No process-start event is treated as a compatibility result. Actual game classifications require a real test report. Release Sentry uses no default PII, no user object, no replay, no network breadcrumbs, and no tracing sample by default; optional dSYM upload occurs only outside the app when `SENTRY_AUTH_TOKEN` is supplied to the packaging environment.
