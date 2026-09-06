# Runtime architecture and build

Read [ARCHITECTURE.md](ARCHITECTURE.md) for the application flow,
[SECURITY.md](SECURITY.md) for trust checks, and [STATUS.md](STATUS.md) for dated
validation evidence. This document describes the implementation at the audit
commit; a script or executable is not evidence of a successful build or Steam
window.

## Components and source ownership

The runtime is downloaded separately from `Portside.app`. Three archives form
one installed wrapper:

| Component                                     | Source and producer                                                                                                                                                                                                    | Installed responsibility                                                                                                                                                       |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `PortsideWrapper-<runtime-version>.tar.xz`    | [wrapper template](../runtime/wrapper-template/Contents/Info.plist), [PortsideRuntimeHost](../apps/runtime-host/Sources/PortsideRuntimeHost/main.swift), [build-wrapper.sh](../scripts/build-runtime/build-wrapper.sh) | Archive root `PortsideBaseline.app`; native launcher and baseline configuration.                                                                                               |
| `PortsideWineEngine-<runtime-version>.tar.xz` | Locked `vendor/wine`, [build-wine-engine.sh](../scripts/build-runtime/build-wine-engine.sh), then [fetch-engine.sh](../scripts/build-runtime/fetch-engine.sh)                                                          | Wine loader, wineboot, wineserver, libraries and Windows support files. Archive root follows the runtime version; manifest component version identifies the persistent engine. |
| `PortsideWinetricks-<runtime-version>.tar.xz` | Locked `vendor/winetricks`, [build-winetricks.sh](../scripts/build-runtime/build-winetricks.sh)                                                                                                                        | Vendored executable script, verbs and notices used to install Steam.                                                                                                           |

`PortsideRuntimeHost` belongs to the mutable runtime wrapper. `PortsideAgent`
is a separate helper inside the signed desktop bundle; it supervises activity
and prepares runtime updates after the main app closes. Neither is the Wine
engine or Steam. Sparkle updates the desktop bundle, including its helpers;
it does not distribute the runtime archives.

[upstream/lock.json](../upstream/lock.json) records upstream repository, full
commit, snapshot checksum, license inventory and source location.
[upstream/dependencies.json](../upstream/dependencies.json) records intended
build dependency versions, origins, checksums and licenses. Other `vendor/`
snapshots preserve source provenance and notices; they are not production
binaries or authoritative Portside documentation. Source changes go through
[upstream sync](../scripts/upstream/sync.sh) or documented
`upstream/patches/`, never manual snapshot surgery. The build recipe currently
copies Wine sources without a patch-application step; adding a patch file alone
does not establish that it is applied.

Sikarugir source repositories are legitimate provenance inputs. Precompiled
Sikarugir releases are not Portside builds and must never become a hidden
commercial fallback. Steam is obtained from Valve by the `steam` winetricks
verb at user setup; it is not mirrored or bundled. On Apple silicon,
[RosettaManager](../apps/desktop/Sources/PortsideCore/RuntimePipeline.swift)
probes x86 execution and can invoke Apple's `softwareupdate` to install Rosetta.
Rosetta and Steam therefore remain external installation dependencies.

## Engine build versus runtime assembly

[build-engine.sh](../scripts/build-runtime/build-engine.sh) produces a persistent
engine using the local Wine snapshot. [resolve-engine.sh](../scripts/build-runtime/resolve-engine.sh)
derives `wine-<WineVersion>-<first-12-commit-characters>` and storage prefix
`runtime/engines/validated/<engine-version>/`. Metadata binds the archive name,
storage key, size, SHA-256, Wine commit/snapshot checksum, Portside commit,
build ID and observed compiler/Xcode/macOS information.

The Wine recipe builds native tools first, then a macOS engine with i386 and
x86_64 PE support. Supported host/target pairs in the script are arm64/arm64,
x86_64/x86_64 and arm64/x86_64; the workflow uses `macos-15` and defaults to the
host architecture. Wine's upstream tests are explicitly disabled. A local
cache can reuse an install tree; a matching cache is an optimization, not the
durable engine source.

[build.sh](../scripts/build-runtime/build.sh) audits input presence, builds the
wrapper, fetches the engine matching the lockfile from Portside storage,
repackages it under the runtime version, packages winetricks, and validates
the combined archive layout. It never recompiles Wine. A missing engine or
metadata/hash/size mismatch fails explicitly. There is no supported standalone
local-engine input to bypass this fetch.

Build outputs include unsigned manifest, archive checksums,
`engine-input.json`, `provenance.json` and `sbom.spdx.json`. Provenance records
both the persistent engine checksum and the repackaged runtime checksum.
[create-archive.sh](../scripts/build-runtime/create-archive.sh) normalizes
staged timestamps, ownership and macOS metadata; byte-identical reproducibility
has not been demonstrated by this audit. The SPDX document inventories three
main packages; it is not evidence of a complete transitive dependency audit.

Important limits visible in the code:

- Homebrew workflow steps install available formulas and print versions; they
  do not enforce the versions or source checksums in the dependency JSON.
- The persistent key omits architecture, toolchain and patch identity.
  [publish_engine.sh](../scripts/publish_engine.sh) uses ordinary `aws s3 cp`,
  without a conditional write preventing replacement of an existing key.
  Versioned naming alone does not prove immutable storage.
- Engine provenance is generated and retained in the workflow artifact, but
  the engine publisher uploads only archive, checksum and metadata.
- `source-audit.sh` checks source presence. Snapshot hygiene is checked by
  [validate_snapshot.sh](../scripts/upstream/validate_snapshot.sh) and the
  [production policy](../scripts/validate-production-policy.sh); a successful
  presence check is not a recalculation of every lockfile checksum.

## Manifest and publication boundary

The generated schema-2 manifest uses channel/build status `production`,
`builtBy`, build ID, Portside commit, manifest/minimum-app versions, renderer
defaults, compatibility rules and three components. Each component has a URL,
SHA-256, size, version, source commit/checksum and license. Manifest and
component rollback fields are initially null.

[generate_manifest.sh](../scripts/generate_manifest.sh) canonicalizes sorted
JSON with `signature: null` and `signatureKeyId`, signs using an external
Ed25519 private-key file, and writes the base64 signature. It overwrites the
input object's signature field for signing; it does not reject a previously
signed input. [validate-manifest.sh](../scripts/build-runtime/validate-manifest.sh)
checks structural fields, HTTPS URLs, component count, hash format and forbidden
legacy references. It accepts unsigned input and does not cryptographically
verify signatures, authorize hosts, or compare archives to their hashes.

The desktop's [backend client](../apps/desktop/Sources/PortsideCore/PortsideBackendClient.swift)
and [manifest verifier](../apps/desktop/Sources/PortsideCore/CommercialInfrastructure.swift)
perform stronger authentication and download checks; backend publication also
verifies Ed25519. See [SECURITY.md](SECURITY.md) for exact boundaries. The
committed [documentation manifest](runtime-manifest.json) and
[backend manifest](../apps/backend/manifests/runtime-manifest.json) are blocked,
empty placeholders; they are not signed usable production releases.

[build-runtime.yml](../.github/workflows/build-runtime.yml) signs and uploads
the runtime automatically to the single configured production bucket. Manifest
URLs use `/v1/runtime/artifacts/production/<fileName>` on the Portside API,
which validates the production channel and filename before returning a temporary
signed storage URL. This runtime route is public and does not check license
entitlement or a published artifact record in the database.
Storage upload does not publish the backend's discovery record: the app release
workflow separately calls [register_runtime_release.sh](../scripts/register_runtime_release.sh).
[RELEASE.md](RELEASE.md) documents that distinction and the absence of staging.

## Installation, prefix and launch

Paths are defined in [PortsidePaths](../apps/desktop/Sources/PortsideCore/PortsideCore.swift).
All entries below are relative to the user's Application Support `Portside`
directory; they are not part of `/Applications/Portside.app`.

| Location                          | Ownership and use                                                                                      |
| --------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `Wrappers/PortsideBaseline.app`   | Replaceable active runtime wrapper.                                                                    |
| `Prefixes/PortsideBaseline`       | Persistent user Wine prefix, Windows registry, Steam installation and account/game data. Preserve it.  |
| `Runtime/Pending`                 | Downloaded update archives and local pending index.                                                    |
| `Runtime/rollback-<time>-<UUID>`  | Prior wrapper; successful installation/startup retention keeps the newest one.                         |
| `Runtime/failed-<time>-<UUID>`    | Failed replacement retained for bounded recovery diagnostics; only the newest one is kept.             |
| `Cache/Downloads`, `Cache/XDG`    | Artifact and runtime-tool caches.                                                                      |
| `Manifests`                       | Cached manifest and ETag.                                                                              |
| `SteamLibrary`                    | Created application directory and scan root; source does not establish that Steam installs games here. |
| `Logs`, `Diagnostics`, `Profiles` | Local operational state; inspect only with appropriate sanitization.                                   |

[PortsideRuntimeInstaller](../apps/desktop/Sources/PortsideCore/PortsideRuntimePipeline.swift)
extracts archives into a temporary cache directory, combines components under
`Contents/SharedSupport`, and changes engine `share-wine` into `share/wine`.
It applies the baseline and moves the previous wrapper into a rollback folder
before moving the candidate into place. The installed wrapper's
`Contents/SharedSupport/prefix` symlinks to the persistent managed prefix.
Existing managed prefixes are reused; new ones use `wineboot -u` through the
host. Source does not establish migration of arbitrary legacy in-wrapper or
native macOS Steam data; never improvise that migration by copying credentials.

The baseline [runtime configuration](../runtime/wrapper-template/Contents/Resources/portside-runtime.json)
selects WineD3D, enables MSYNC/ESYNC and disables D3DMetal/DXMT/DXVK. The host
constructs `Process` executable/argument arrays and directly runs winetricks
through its shebang. Commands are `--version`, `--create-prefix`,
`--winetricks <verb>`, `--program <program>`, or Steam by default. Relevant
runtime variables are `WINEPREFIX`, `WINEARCH`, `WINEDEBUG`, `WINE`,
`WINESERVER`, `WINELOADER`, `WINEMSYNC`, `WINEESYNC`, `D3DMETAL`, `DXMT`,
`DXVK`, `PATH` and `XDG_CACHE_HOME`. Do not log their sensitive values.

Storage maintenance runs after a successful runtime installation and on startup
only when the active wrapper validates. It retains one rollback, one failed
wrapper and the newest legacy `Backups/Steam-prefix-*` recovery point. Direct
temporary extraction directories under `Cache` and incomplete pending staging
directories older than 24 hours are removed. Symlinks, unrelated names, the
managed prefix and game libraries are excluded. This bounds future accumulation
without treating user-owned Steam data as disposable cache.

The Steam flow installs the `steam` verb, launches the wrapper for the initial
updater cycle and launches it again for interactive use. Subsequent desktop
startup performs app/runtime checks and offers Open Steam. The detached wrapper
and Agent permit activity after the primary UI closes. Lease/handoff logic
serializes foreground bootstrap and the Agent's update worker; see
[UPDATE_ARCHITECTURE.md](UPDATE_ARCHITECTURE.md). These process relationships
are implemented; real interactive continuity remains a separate GUI test.

## Update, preservation and rollback limits

Runtime download/staging is separate from app updates. Accepted artifacts are
hashed during download/cache verification; pending files are staged before
installation while Steam is stopped. Offline behavior can use a previously
verified manifest and installed runtime, subject to minimum-app gates.

“Atomic installation” is the name of a move-based helper, not a proven
transaction across the whole setup. Final prefix setup/layout validation occurs
after replacing the active wrapper. Pending-update application attempts rollback
on an exception; direct setup/repair calls do not provide that same catch path.
New rollback names contain a sortable creation timestamp, and rollback selection
also supports legacy UUID names using filesystem modification dates. The failed
destination is now uniquely timestamped rather than using a literal placeholder.
Crash journaling and a fully transactional prefix/layout transition are still
not established, so reliable end-to-end recovery remains unverified.

The pending-index reader checks file presence/count and relative paths but does
not reverify signature or archive hashes at application time. Archive listing
validation rejects unsafe paths; explicit symlink-target containment is not
established there. Do not describe these paths as complete tamper/crash safety.
Backend rollback has separate restrictions described in [RELEASE.md](RELEASE.md).

Preserving the external managed prefix is implemented intent. No audit result
proves game/save/account preservation through all failures, Wine registry
changes or legacy migrations. Never delete a prefix, Steam installation,
`steamapps`, saves, credential files or an existing user library to recover a
runtime. WineD3D build success also does not validate every game's renderer,
anti-cheat, launcher or compatibility.

## Commands and validation boundaries

Run from the repository root. These commands exist; the audit did not build
Wine, download runtime artifacts, launch Steam or access production services.

```sh
./scripts/build-runtime/source-audit.sh
./scripts/upstream/validate_snapshot.sh vendor/wine
./scripts/upstream/validate_snapshot.sh vendor/winetricks
./scripts/build-runtime/resolve-engine.sh
./scripts/validate-production-policy.sh
for script in scripts/build-runtime/*.sh scripts/upstream/*.sh; do sh -n "$script"; done
```

A local engine build needs macOS, Xcode and the tooling described above, and
writes disposable build/cache output:

```sh
PORTSIDE_ENGINE_BUILD_DIR="$PWD/build/engine" \
  ./scripts/build-runtime/build-engine.sh
```

Assembly additionally needs AWS CLI and externally configured engine-storage
credentials. `PORTSIDE_RUNTIME_VERSION`, `PORTSIDE_RUNTIME_CHANNEL` and
`PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX` configure the result:

```sh
PORTSIDE_RUNTIME_VERSION=0.1.0 \
PORTSIDE_RUNTIME_CHANNEL=production \
PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX=https://api.example.invalid/v1/runtime/artifacts/production/ \
  ./scripts/build-runtime/build.sh
```

The example URL is a placeholder; use an approved API prefix for any intended
release. Required storage variable names
are in [RELEASE.md](RELEASE.md); `fetch-engine.sh` also supports
`PORTSIDE_ENGINE_BUCKET`, `PORTSIDE_ENGINE_ACCESS_KEY_ID`,
`PORTSIDE_ENGINE_SECRET_ACCESS_KEY`, `PORTSIDE_ENGINE_REGION` and
`PORTSIDE_ENGINE_ENDPOINT` overrides. Local controls include
`PORTSIDE_RUNTIME_BUILD_DIR`, `PORTSIDE_ENGINE_BUILD_DIR`,
`PORTSIDE_WINE_CACHE_DIR`, `PORTSIDE_WINE_FORCE_REBUILD`, `PORTSIDE_WINE_ARCH`
and `PORTSIDE_BUILD_JOBS`; compiler flag overrides are defined in the Wine recipe.

For produced runtime files:

```sh
PORTSIDE_RUNTIME_VERSION=0.1.0 ./scripts/build-runtime/validate-clean-layout.sh
./scripts/build-runtime/validate-manifest.sh build/runtime/runtime-manifest-unsigned.json
```

Layout checks establish file presence, executable permissions and baseline
structure, not successful Wine execution. Follow [TESTING.md](TESTING.md) for
host/desktop tests and operator-assisted clean installation. That script removes
its configured clean root; use a newly allocated disposable location, never an
existing user-data directory. A noninteractive workflow cannot confirm its GUI
prompts. There is also a source-inferred fixture-layout blocker: the archive
retains the template prefix directory, and the clean-install script uses `ln -s`
into it without first replacing that directory. This nests the link, leaving
the host prefix different from the script's external `steam.exe`/marker checks.
It was not executed in this audit; fix/validate that harness before claiming a
complete clean-install run. See [VALIDATION.md](VALIDATION.md).
A Steam process, executable, Dock icon or successful archive build
never proves a rendered, interactive Steam window or a running game.
