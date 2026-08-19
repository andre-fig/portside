# Portside architecture

## Boundaries

`PortsideCore` contains orchestration and persistence:

- `SystemRequirements` validates Apple silicon and free storage.
- `EnvironmentStore` owns `~/Library/Application Support/Portside` and creates `Runtime`, `Prefix/Steam`, `Backups`, `Logs`, `Cache`, `Downloads`, and `Diagnostics`. Existing prefixes are preserved; runtime transitions use retained snapshots and do not migrate legacy directories automatically.
- `SecureDownloader` accepts HTTPS URLs only, downloads to a private destination, and records SHA-256.
- `SteamInstaller` owns the Valve installer URL and invokes it only through a discovered runtime, never through a shell.
- `SteamInstaller` keeps installer arguments separate from the normal launch. `steam.exe` is launched with an empty `Process.arguments` list and no shell.
- `FreeWineRuntimeProvider` is the concrete provider: pinned Wine 11.6_1, SHA-256 verification, resumable download, safe tar extraction, user-local GStreamer extraction, Rosetta detection, recoverable prefix snapshots, idempotent prefix initialization, and runtime record persistence.
- `RosettaManager` validates and requests Apple’s official Rosetta installation automatically when required; any protected macOS confirmation remains owned by macOS.
- `SteamReadinessMonitor` observes only the Portside-owned process tree and requests activation through `NSRunningApplication`; it never captures another application's pixels, so Portside does not request Screen Recording permission. It reports process handoff, not visual login success.
- `SteamProcessLauncher` starts the Windows client directly through Wine with separated arguments and the inherited Wine environment. A POSIX launch lock prevents concurrent Portside instances from creating duplicate Steam trees, and the monitor force-terminates only Steam processes associated with the managed prefix when a strategy is replaced or setup fails.
- `ProcessSupervisor` is retained as a generic process utility for tests and recovery. The direct Wine launcher owns the single normal launch, while readiness remains the monitor's responsibility. Shutdown first requests `wineserver -k`, then terminates only Steam processes associated with the managed prefix.
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
4. Verify/install GStreamer locally and download Wine 11.6_1.
5. Verify and extract the runtime atomically.
6. Initialize the Steam prefix with `wineboot` through `Process`.
7. Download `SteamSetup.exe`.
8. Install Steam into the Portside Steam prefix with `/S` through the injected process runner.
9. Verify `steam.exe` exists and is executable.
10. Acquire the Portside launch lock and start exactly one Wine-hosted Steam process with an empty Steam argument list and the inherited environment.
11. Observe the managed Steam/webhelper process tree for a stable handoff, activate the owning process, and close Portside. No display pixels are captured, so visual login rendering remains an interactive validation step.

No process-start event is treated as a compatibility result. Actual game classifications require a real test report. Release Sentry uses no default PII, no user object, no replay, no network breadcrumbs, and no tracing sample by default; optional dSYM upload occurs only outside the app when `SENTRY_AUTH_TOKEN` is supplied to the packaging environment.
