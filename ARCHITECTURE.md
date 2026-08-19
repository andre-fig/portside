# Portside architecture

## Boundaries

`PortsideCore` contains orchestration and persistence:

- `SystemRequirements` validates Apple silicon and free storage.
- `EnvironmentStore` owns `~/Library/Application Support/Portside` and creates `Runtime`, `Prefix/Steam`, `Logs`, `Cache`, `Downloads`, and `Diagnostics`. An older `Prefixes/Steam` directory is migrated in place without deleting its contents.
- `SecureDownloader` accepts HTTPS URLs only, downloads to a private destination, and records SHA-256.
- `SteamInstaller` owns the Valve installer URL and invokes it only through a discovered runtime, never through a shell.
- `FreeWineRuntimeProvider` is the concrete provider: pinned Wine 11.15, SHA-256 verification, resumable download, safe tar extraction, user-local GStreamer extraction, Rosetta detection, idempotent prefix initialization, and runtime record persistence.
- `RosettaManager` validates and, only after an explicit user action, requests Apple’s official Rosetta installation.
- `SteamReadinessMonitor` combines process snapshots with public CoreGraphics window inspection; a started process is not treated as a ready Steam session.
- `ProcessSupervisor` owns the Steam process lifecycle.
- `DiagnosticReport` writes a sanitized report without credentials or tokens.

The SwiftUI target owns onboarding, progress, dashboard, and Support. The Steam UI remains the Steam client. DXMT is not installed because its current upstream repository reports no asserted license; WineD3D, which ships with Wine, is used for Direct3D 9/10/11.

## Security decisions

All remote downloads are HTTPS and the installer host is fixed. Process launch uses `Process` with a fixed array of arguments and a controlled environment. All diagnostic/log output is sanitized. Portside never asks for a Steam password and never writes credentials.

## Lifecycle

1. Load persisted state.
2. Validate machine and storage.
3. Create the private workspace.
4. Verify/install GStreamer locally and download Wine 11.15.
5. Verify and extract the runtime atomically.
6. Initialize the Steam prefix with `wineboot` through `Process`.
7. Download `SteamSetup.exe`.
8. Install Steam into the Portside Steam prefix with `/S` through the injected process runner.
9. Verify `steam.exe` exists and is executable.
10. Bootstrap Steam with `-silent` and wait for the installed-client marker.
11. Start Steam normally and wait for its window.

No process-start event is treated as a compatibility result. Actual game classifications require a real test report.
