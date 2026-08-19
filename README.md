# Portside

**Your Steam library, now on Mac.**

Portside is a native SwiftUI macOS wrapper that prepares a private compatibility workspace and launches the official Windows Steam client. It does not replace Steam’s library UI, collect Steam credentials, distribute games, or bypass DRM/anti-cheat.

This repository contains a compilable MVP shell for Apple silicon. It downloads `SteamSetup.exe` from Valve’s official CDN during setup. A compatibility runtime is deliberately not bundled: commercial redistribution requires a separately reviewed license. For local development, an authorized runtime executable may be placed at `~/Library/Application Support/Portside/Runtime/bin/wine` or `wine64`.

## Build and test

```sh
swift build
swift test
./scripts/package_app.sh
open build/Portside.app
```

The package targets macOS 13+ and builds the current architecture by default. `package_app.sh` produces an arm64 `.app` bundle and does not claim signing or notarization.

## MVP behavior

- First launch performs Apple silicon and storage checks, creates the Portside directory tree, and downloads the official Steam installer over HTTPS.
- If an authorized runtime is available, the installer is invoked with a fixed argument list and the expected Steam executable is verified.
- Without a runtime, setup stops with a user-facing explanation rather than silently installing an unlicensed component.
- Support includes environment checks, repair guidance, diagnostic export, storage access, cache clearing, and destructive reset confirmation.
- Compatibility profiles are optional metadata keyed by numeric Steam App ID. `3139440` (GunZ: The Duel) is not allowlisted and is not bundled.

The real Steam/game validation matrix remains pending until Steam and an authorized runtime can be run on the target Mac. See `docs/VALIDATION.md`.
