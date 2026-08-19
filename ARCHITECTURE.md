# Portside architecture

## Boundaries

`PortsideCore` contains platform-independent orchestration and persistence:

- `SystemRequirements` validates Apple silicon and free storage.
- `EnvironmentStore` owns `~/Library/Application Support/Portside` and creates `Runtime`, `Prefixes/Steam`, `Profiles`, `Logs`, `Cache`, `Downloads`, and `Diagnostics`.
- `SecureDownloader` accepts HTTPS URLs only, downloads to a private destination, and records SHA-256.
- `SteamInstaller` owns the Valve installer URL and invokes it only through a discovered runtime, never through a shell.
- `RuntimeLocating` is the replacement seam for a future licensed runtime package.
- `ProcessSupervisor` owns the Steam process lifecycle.
- `ProfileStore` stores optional, non-authorizing compatibility metadata.
- `DiagnosticReport` writes a sanitized report without credentials or tokens.

The SwiftUI target owns onboarding, progress, dashboard, and Support. The Steam UI remains the Steam client. Windows-specific behavior is intentionally behind `RuntimeLocating`; proprietary components are not copied into this repository.

## Security decisions

All remote downloads are HTTPS and the installer host is fixed. Process launch uses `Process` with a fixed array of arguments and a controlled environment. App IDs must be digits only, and all diagnostic/log output is sanitized. Portside never asks for a Steam password and never writes credentials.

## Lifecycle

1. Load persisted state.
2. Validate machine and storage.
3. Create the private workspace.
4. Download `SteamSetup.exe`.
5. Discover an authorized runtime.
6. Install Steam into the Portside Steam prefix.
7. Verify `Steam.exe` exists.
8. Start Steam and keep its process associated with Portside.

No process-start event is treated as a compatibility result. Actual game classifications require a real test report.
