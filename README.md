# Portside

**Your Steam library, now on Mac.**

Portside is a native SwiftUI macOS wrapper that prepares a private compatibility workspace and launches the official Windows Steam client. It does not replace Steam’s library UI, collect Steam credentials, distribute games, or bypass DRM/anti-cheat.

This repository contains a native Apple silicon MVP. During setup it downloads a pinned Wine Staging 11.15 macOS build, verifies its SHA-256, safely extracts it into Portside’s private runtime directory, downloads the official GStreamer 1.28.5 runtime package, verifies and extracts it locally, creates a win64 prefix, and downloads `SteamSetup.exe` from Steam’s official Fastly CDN. WineD3D is the default graphics layer for Direct3D 9/10/11. No runtime or Steam binary is bundled in the app.

## Build and test

```sh
swift build
swift test
./scripts/package_app.sh
open build/Portside.app
```

The package targets macOS 13+ and builds the current architecture by default. `package_app.sh` produces an arm64 ad-hoc-signed `.app` bundle; it is not notarized.

## MVP behavior

- Rosetta is detected by executing a harmless x86-64 `/usr/bin/true`; if missing, Portside offers the official macOS installation flow.
- The runtime manifest is fixed to Wine 11.15 and includes release checksum, source, architecture, license note, and validation date.
- The installer is invoked with a fixed argument list and the expected Steam executable is verified.
- The Windows installer is run silently with the separate, case-sensitive `/S` argument; its output is captured internally and never shown in the Portside UI.
- Steam bootstrap is attempted with `-silent`, validated using its installed-client marker, and followed by controlled CEF launch strategies for login (`normal`, `-cef-disable-gpu`, then `-cef-disable-gpu -cef-disable-gpu-compositing`).
- Steam launches explicitly with the US English language argument and does not inherit a Portuguese locale from an existing Wine prefix.
- The first launch starts setup automatically in a single native progress window; after a valid installation, Portside launches and supervises one Steam process directly through Wine, then exits its own interface.
- Wine crash dialogs are disabled in the private prefix and `winedbg.exe` is disabled for Portside-owned processes; failures are logged and surfaced as recoverable Portside errors.
- Sentry starts invisibly through `DiagnosticsService`; Release events use sanitized structured CEF/readiness context only, with PII, full log attachments, and tracing disabled by default.
- Download interruptions leave a `.part` file and resume with HTTP Range requests.
- Archive entries are preflighted for absolute paths and `..` traversal before extraction.
- Recoverable failures provide a single retry action; technical diagnostics are sent automatically through the configured Sentry integration.
- Portside has no game catalog or App ID allowlist; Steam remains responsible for the library and game installation.

The real Steam/game validation matrix still requires completing the first zero-click setup on an interactive GUI session. See `docs/VALIDATION.md`.
