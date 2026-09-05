# Script and configuration catalog

Use [ARCHITECTURE](ARCHITECTURE.md) for the monorepo map,
[DEVELOPER_GUIDE](DEVELOPER_GUIDE.md) for setup and [TESTING](TESTING.md) for checks.
This catalog identifies script responsibility; it does not authorize execution.

## Application and configuration owners

| Location                                                                                                                                         | Responsibility                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| [Desktop Package.swift](../apps/desktop/Package.swift) and [Package.resolved](../apps/desktop/Package.resolved)                                  | Four products, two test targets, Sparkle/Sentry resolution                       |
| [Desktop Resources](../apps/desktop/Resources)                                                                                                   | App/agent metadata and entitlements; release scripts inject public configuration |
| [Runtime host package](../apps/runtime-host/Package.swift)                                                                                       | Standalone native wrapper executable and tests                                   |
| [Wrapper template](../runtime/wrapper-template)                                                                                                  | Portside-owned identity and runtime defaults; compiled host/engine are generated |
| [Backend package](../apps/backend/package.json), [schema](../apps/backend/prisma/schema.prisma), [migrations](../apps/backend/prisma/migrations) | npm commands/dependencies and database contract                                  |
| [Backend Dockerfile](../apps/backend/Dockerfile), [Railway guide](RAILWAY_DEPLOYMENT.md)                                                         | Container and API/worker/cron start configuration                                |
| [Landing package](../apps/landing/package.json), [Vite config](../apps/landing/vite.config.ts)                                                   | Bun scripts, React/TanStack/Nitro build and server                               |
| [Source lock](../upstream/lock.json), [dependencies](../upstream/dependencies.json)                                                              | Source identity, licenses/checksums and intended Wine build tools                |
| [UPSTREAM_VERSIONS](../UPSTREAM_VERSIONS.json)                                                                                                   | Compatibility pointer to the source lock, not a binary catalog                   |
| [Workflows](../.github/workflows), [hooks](../.githooks), [gitignore](../.gitignore)                                                             | Automation triggers, local checks and generated/private exclusions               |

The committed runtime JSON files in [docs](runtime-manifest.json) and
[backend manifests](../apps/backend/manifests) are blocked/example fixtures,
not deployed release evidence. Package/default versions do not identify the
latest published app or runtime.

## Application release scripts

Read [RELEASE](RELEASE.md) for sequence, required names and limits.

| Script                                                                | Responsibility / side effect                                                                            |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| [package_app.sh](../scripts/package_app.sh)                           | Local development app, helper bundles, ad hoc signing and dSYM; optional Sentry upload when configured  |
| [build_release.sh](../scripts/build_release.sh)                       | Configured unsigned release bundle and dSYM; public plist configuration                                 |
| [sign_release.sh](../scripts/sign_release.sh)                         | Sign the previously selected runtime manifest, nested and outer Developer ID codesign, intermediate ZIP |
| [notarize_release.sh](../scripts/notarize_release.sh)                 | Apple submissions; staple app/DMG, recreate final ZIP, checksums                                        |
| [create_dmg.sh](../scripts/create_dmg.sh)                             | Compressed UDZO DMG containing only Portside.app                                                        |
| [validate_release_bundle.sh](../scripts/validate_release_bundle.sh)   | App/Agent metadata, app/Installer signature, English metadata and DMG checks                            |
| [generate_appcast.sh](../scripts/generate_appcast.sh)                 | Sign update archives with Sparkle EdDSA and generate appcast enclosures                                 |
| [generate_manifest.sh](../scripts/generate_manifest.sh)               | Ed25519 signing of unsigned runtime JSON using external private key                                     |
| [publish_release.sh](../scripts/publish_release.sh)                   | Upload app/release and runtime metadata/archives to the configured bucket                               |
| [publish_runtime.sh](../scripts/publish_runtime.sh)                   | Upload runtime archives/manifest/provenance/SBOM to production storage                                  |
| [register_runtime_release.sh](../scripts/register_runtime_release.sh) | Authenticated source/build/release/manifest registration in the API                                     |
| [publish_engine.sh](../scripts/publish_engine.sh)                     | Upload engine archive/checksum/metadata; use explicit build directory as in workflow                    |

## Engine and runtime scripts

Read [RUNTIME](RUNTIME.md) before running these scripts. Engine build and runtime
assembly are different operations; ordinary assembly does not compile Wine.

| Script                                                                        | Responsibility                                                                                        |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| [build.sh](../scripts/build-runtime/build.sh)                                 | Assemble wrapper/engine/winetricks and unsigned runtime evidence                                      |
| [build-engine.sh](../scripts/build-runtime/build-engine.sh)                   | Compile and package persistent Wine engine with metadata/provenance                                   |
| [build-wine-engine.sh](../scripts/build-runtime/build-wine-engine.sh)         | Configure/make/install vendored Wine with Darwin and PE toolchain                                     |
| [build-wrapper.sh](../scripts/build-runtime/build-wrapper.sh)                 | Compile host, populate wrapper template and archive                                                   |
| [build-winetricks.sh](../scripts/build-runtime/build-winetricks.sh)           | Package vendored winetricks script, verb and notices                                                  |
| [resolve-engine.sh](../scripts/build-runtime/resolve-engine.sh)               | Read lock/VERSION and derive engine identity/storage key; read-only                                   |
| [fetch-engine.sh](../scripts/build-runtime/fetch-engine.sh)                   | Fetch/copy engine metadata and archive; validate source identity/hash/size/layout                     |
| [changed-components.sh](../scripts/build-runtime/changed-components.sh)       | Classify Git changes as engine or assembly; exit status is the boolean result                         |
| [create-archive.sh](../scripts/build-runtime/create-archive.sh)               | Normalize archive entries/ownership/timestamps; reproducibility mechanism, not proof                  |
| [source-audit.sh](../scripts/build-runtime/source-audit.sh)                   | Check required source inputs exist; not full checksum/license validation                              |
| [validate-clean-layout.sh](../scripts/build-runtime/validate-clean-layout.sh) | Extract artifacts in a temporary area and inspect host/engine/winetricks layout                       |
| [validate-manifest.sh](../scripts/build-runtime/validate-manifest.sh)         | Structural production-manifest validation, not cryptographic verification                             |
| [validate-clean-install.sh](../scripts/validate-clean-install.sh)             | Destructive only to its selected disposable root; installs Steam and requires manual GUI confirmation |

## Source and local policy scripts

| Script                                                                             | Responsibility                                                                           |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [sync.sh](../scripts/upstream/sync.sh)                                             | Network source synchronization; replaces managed snapshots and updates lock after checks |
| [validate_snapshot.sh](../scripts/upstream/validate_snapshot.sh)                   | Nested-Git/generated-directory and escaping-symlink rejection                            |
| [snapshot_checksum.sh](../scripts/upstream/snapshot_checksum.sh)                   | Deterministic source file/path/symlink digest                                            |
| [license_inventory_checksum.sh](../scripts/upstream/license_inventory_checksum.sh) | License/notice inventory digest                                                          |
| [validate-production-policy.sh](../scripts/validate-production-policy.sh)          | Production source/URL policy and snapshot layout checks                                  |
| [install-git-hooks.sh](../scripts/install-git-hooks.sh)                            | Set repository hook configuration                                                        |
| [pre-commit.sh](../scripts/hooks/pre-commit.sh)                                    | Staged whitespace/shell/JSON and optional workflow checks                                |
| [pre-push.sh](../scripts/hooks/pre-push.sh)                                        | Target checks to paths in the outgoing commit range; no release publication              |

There is no active staging-promotion script. References to one in history are
superseded; see [DECISIONS](DECISIONS.md). A patch directory is referenced by
build-change detection but no checked-in patch set exists at the audit base;
do not infer that the current Wine recipe applies patches.
