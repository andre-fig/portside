# Portside

Portside is a native SwiftUI macOS app that prepares a private Wine runtime
wrapper and opens the official Windows Steam client. It targets macOS 13+ on
Apple silicon. Steam is obtained from Valve through winetricks; games, account
sessions and DRM/anti-cheat bypasses are not distributed by Portside.

## Download

[Download the latest production Portside DMG](https://api-production-6d06.up.railway.app/app/production/latest).
The stable API endpoint redirects to the currently registered production DMG;
temporary signed storage URLs should not be copied or bookmarked.

Start with [AGENTS.md](AGENTS.md) for working rules and
[docs/README.md](docs/README.md) for the documentation map. The
[audit snapshot](docs/STATUS.md) distinguishes local evidence, implementation,
pending validation and external state that was not checked.

## Development

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/package_app.sh
```

The packaging command creates a development bundle with ad hoc signing by
default. It does not establish commercial signing, notarization or working Steam.
See [setup](docs/DEVELOPER_GUIDE.md), [test matrix](docs/TESTING.md) and
[release runbook](docs/RELEASE.md) before other build/release steps.

## System map

| Area                                        | Responsibility                                                              |
| ------------------------------------------- | --------------------------------------------------------------------------- |
| [Desktop](apps/desktop/AGENTS.md)           | SwiftUI app, reusable core, background agent and app installer              |
| [Runtime host](apps/runtime-host/AGENTS.md) | Native executable inside the private wrapper                                |
| [Backend](docs/BACKEND.md)                  | API, licenses, manifest/appcast delivery, artifact records, worker and cron |
| [Landing](apps/landing/README.md)           | Public site and Stripe checkout; fulfillment remains incomplete             |
| [Runtime](docs/RUNTIME.md)                  | Portside wrapper, source-built Wine engine and vendored winetricks          |
| [Upstream](docs/UPSTREAM_MIRRORING.md)      | Source snapshots, locks, notices and synchronization                        |

Sparkle updates `Portside.app`; a separately signed runtime manifest selects
wrapper/engine/winetricks artifacts. Commercial bootstrap first requires
`/Applications/Portside.app`, then completes app-update preflight before license
and runtime work. See [architecture](docs/ARCHITECTURE.md) and
[security](docs/SECURITY.md) for the actual trust and data boundaries.

Current workflows use one production channel and one artifact bucket. Workflow
configuration is not evidence that GitHub, Railway, Apple, Stripe or storage are
currently operational. See [decisions](docs/DECISIONS.md) before changing these
boundaries and [licensing](LICENSING.md) for source/distribution obligations.
