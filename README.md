# Portside

**Your Steam library, now on Mac.**

Portside is a native SwiftUI macOS app that prepares one private, user-local
runtime wrapper and opens the official Windows Steam client. It preserves the
Portside identity, Sentry boundary, sanitized diagnostics and rotating logs.
It does not distribute games, copy a native Steam session, bypass DRM or
anti-cheat, or expose Sikarugir Creator to the end user.

## Build and test

~~~sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/package_app.sh
open build/Portside.app
~~~

The `Build Desktop` GitHub Actions workflow runs after a successful `CI` run
on `main` (or manually) and publishes the unsigned validation build as
`Portside.app.zip`, `Portside.dmg`, its checksum file and debug symbols.

## Monorepo layout

The repository keeps the two deployable products isolated:

```text
apps/desktop/   Native macOS client, Swift Package and tests
apps/backend/   NestJS API, Prisma schema, worker and sync job
docs/           Product, security, validation and deployment documentation
scripts/        Release packaging, signing and publishing automation
```

After the first setup, Portside stays ready and opens Steam only when you
choose `Open Steam`; closing Steam does not launch it again.

The package targets macOS 13+ on Apple silicon. Rosetta 2 is detected and
installed only when missing through Apple’s official softwareupdate mechanism.
Portside-produced runtime assets are downloaded from the signed Portside
manifest to the Portside Application Support directory and never embedded in
Portside.app. Upstream source snapshots are versioned under `vendor/`; they are
not a production download fallback.

## Official Sikarugir baseline

The first wrapper is isolated as PortsideBaseline.app and uses the values
validated against the original Sikarugir flow:

~~~text
Creator provenance: 1.0.1
Wrapper template: 1.0.11
Engine: WS12WineSikarugir10.0_6
Renderer: WineD3D
D3DMetal/DXMT/DXVK: disabled
MSYNC/ESYNC: enabled
WINEDEBUG: -plugplay,+loaddll
Program: /Program Files (x86)/Steam/steam.exe
Steam install: official WSS-winetricks steam verb
~~~

The first install waits for the official winetricks process and its Steam
updater to finish. A second clean wrapper opening then waits for a real
on-screen window. A process, Dock icon or steamwebhelper without a window is
not considered UI success.

Managed state is separated into Runtime, Wrappers, Prefixes, SteamLibrary,
Cache, Logs, Diagnostics, Profiles and Manifests. Steam games remain outside
versioned wrapper assets; Portside never copies a whole steamapps tree during
runtime changes.

## Compatibility

GameCompatibilityService stores a versioned manifest indexed by Steam App ID
and executable. It detects PE architecture and common graphics APIs and
orders the official renderer fallbacks described in ARCHITECTURE.md. Unknown
games use a bounded, observable fallback sequence and record only a
functional result. No anti-cheat bypass is attempted.

See docs/runtime-manifest.json, docs/VALIDATION.md, THIRD_PARTY_NOTICES.md and
SIKARUGIR_AUTHORIZATION.md.

## Commercial infrastructure

The commercial control plane is scaffolded separately in `apps/backend/`. It uses
NestJS, PostgreSQL/Prisma, private object storage, signed runtime manifests,
Sparkle 2 app updates and one-Mac license activation. Start with
`docs/COMMERCIALIZATION.md`, `docs/BACKEND.md` and
`docs/RAILWAY_DEPLOYMENT.md`. No Railway deployment, Developer ID signature or
notarization is present in this repository until the owner's credentials and
external approvals are supplied.
