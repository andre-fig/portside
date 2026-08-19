# Portside

**Your Steam library, now on Mac.**

Portside is a native SwiftUI macOS app that prepares a private Wine workspace and launches the official Windows Steam client. It does not replace Steam’s library UI, collect Steam credentials, distribute games, or bypass DRM/anti-cheat.

## Build and test

```sh
swift test
swift build
./scripts/package_app.sh
open build/Portside.app
```

The package targets macOS 13+ on Apple silicon. The app does not bundle Wine or Steam binaries; setup downloads the pinned runtime and the official Steam installer over HTTPS and verifies the runtime checksum before installation.

## Runtime and launch behavior

- Release uses one runtime: Gcenx Wine Staging 11.6_1, with the pinned metadata in [`docs/runtime-manifest.json`](docs/runtime-manifest.json).
- WineD3D is the graphics layer for Direct3D 9/10/11. D3DMetal, GPTK, Sikarugir Launcher and Sikarugir Creator are not bundled.
- The existing Portside prefix is preserved. A recovery point is created before a runtime transition using an APFS clone when available, or targeted Wine registry/link files otherwise; `steamapps`, saves, caches and user data are not copied or deleted.
- SteamSetup.exe is run silently with the separate `/S` argument. Later, `steam.exe` is launched directly through Wine with the ordered CEF 32-bit login arguments `-udpforce`, `-noreactlogin`, `-allosarches`, and `-cef-force-32bit`. No shell, native macOS Steam installation, native-login migration or GPU fallback cascade is used.
- The app records process start, webhelper start and process handoff separately. It never reports a window or rendered UI without manual visual validation, prevents concurrent Portside launches from creating duplicate managed Steam processes, and closes itself after a stable process handoff.
- Wine crash dialogs are disabled for the private prefix and failures are logged locally and sent to Sentry as sanitized technical events. Screen Recording permission is never requested.

Sikarugir remains a development-only comparison reference. It is not selected by Release because an official, checksum-pinned `WS12WineSikarugir10.0_6` artifact and redistributable runtime package could not be verified.

The real interactive Steam login and library rendering still require validation on a display. See [`docs/VALIDATION.md`](docs/VALIDATION.md).
