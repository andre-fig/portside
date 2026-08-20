# Portside

**Your Steam library, now on Mac.**

Portside is a native SwiftUI macOS app that prepares one private, user-local
runtime wrapper and opens the official Windows Steam client. It preserves the
Portside identity, Sentry boundary, sanitized diagnostics and rotating logs.
It does not distribute games, copy a native Steam session, bypass DRM or
anti-cheat, or expose build tools to the end user.

## Build and test

~~~sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/package_app.sh
open build/Portside.app
~~~

The `Build Desktop` GitHub Actions workflow runs after a successful `CI` run
on `main` (or manually) and publishes the unsigned validation build as
`Portside.app.zip`, `Portside.dmg`, its checksum file and debug symbols. After
a source/runtime merge, `Build Portside Runtime` also builds, signs and
publishes the runtime only to the protected `staging` channel.

## Monorepo layout

The repository keeps the two deployable products isolated:

```text
apps/desktop/        Native macOS client, Swift Package and tests
apps/backend/        NestJS API, Prisma schema, worker and sync job
apps/landing/        Landing page, purchase flow and public commercial pages
apps/runtime-host/   Native host used by the Portside runtime wrapper
runtime/             Portside-owned wrapper template and runtime defaults
vendor/              Audited upstream source snapshots, without nested Git
upstream/            Source locks, dependency locks, licenses and patches
docs/                Product, security, validation and operating documentation
scripts/             Build, validation, release and publication automation
```

The complete folder map, script catalog, artifact origins, DMG procedure and
release/update runbooks are in [`docs/PROJECT_GUIDE.md`](docs/PROJECT_GUIDE.md).
The landing page can be run independently from `apps/landing/`; its CI build
is defined in `.github/workflows/build-landing.yml`.

After the first setup, Portside stays ready and opens Steam only when you
choose `Open Steam`; closing Steam does not launch it again.

The package targets macOS 13+ on Apple silicon. Rosetta 2 is detected and
installed only when missing through Apple’s official softwareupdate mechanism.
Portside-produced runtime assets are downloaded from the signed Portside
manifest to the Portside Application Support directory and never embedded in
Portside.app. Upstream source snapshots are versioned under `vendor/`; they are
not a production download fallback.

## Portside runtime baseline

The first wrapper is isolated as `PortsideBaseline.app` and is produced by
Portside from the checked-in template and native runtime host:

~~~text
Wrapper: Portside template + PortsideRuntimeHost
Engine: Portside Wine build from vendor/wine
Renderer: WineD3D
D3DMetal/DXMT/DXVK: disabled
MSYNC/ESYNC: enabled
WINEDEBUG: -plugplay,+loaddll
Program: /Program Files (x86)/Steam/steam.exe
Steam install: vendored winetricks steam verb
~~~

The first install waits for the winetricks process and Steam updater to finish.
A second clean wrapper opening then waits for a real on-screen window. A
process, Dock icon or steamwebhelper without a window is not considered UI
success. The wrapper, engine and winetricks archives are downloaded only from
the signed Portside runtime manifest.

Managed state is separated into Runtime, Wrappers, Prefixes, SteamLibrary,
Cache, Logs, Diagnostics, Profiles and Manifests. Steam games remain outside
versioned wrapper assets; Portside never copies a whole steamapps tree during
runtime changes.

## Compatibility

GameCompatibilityService stores a versioned manifest indexed by Steam App ID
and executable. It detects PE architecture and common graphics APIs and
orders the supported renderer fallbacks described in ARCHITECTURE.md. Unknown
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
