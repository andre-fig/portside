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
derives `wine-<WineVersion>-<first-12-commit-characters>-x86_64-<recipe-hash>` and storage prefix
`runtime/engines/validated/<engine-version>/`. Metadata binds the archive name,
storage key, size, SHA-256, Wine commit/snapshot checksum, Portside commit,
build ID and observed compiler/Xcode/macOS information.

The Wine recipe builds native tools first, then an **x86_64** macOS engine with
i386 and x86_64 PE support. Supported host/target pairs are x86_64/x86_64 and
arm64/x86_64; the workflow uses `macos-15`. Apple silicon runs the engine through
Rosetta. The tracked Wine Darwin loader's low-address layout cannot execute as
arm64 on the tested macOS; see [the first-launch investigation](STEAM_FIRST_LAUNCH_FIX.md).
An explicit arm64 target is rejected. Wine's upstream tests are disabled, but
[validate-engine-execution.py](../scripts/build-runtime/validate-engine-execution.py)
must execute both PE architectures in a disposable symlinked prefix before
packaging and again after archive extraction. `wine --version` alone is insufficient.
The pre-push hook builds engine-changing outgoing `main` commits locally from a
clean Git export. Its persistent Wine install cache retains the existing recipe,
dependency, architecture, build flags and observed macOS/Xcode/Clang checks.
A successful input for the same outgoing commit can be reused on retry. This is
a complete install cache, not resumable partial compilation. GitHub does not
compile Wine or restore a compiler cache; it verifies the local input and runs
short x64/x86 execution controls after safe extraction, before Linux publication.
Native and PE compiler prefix maps replace the developer checkout path, and
Wine uses a virtual `/opt/portside-wine` install prefix with disposable DESTDIR
installation. The packaged and extracted engine must pass a personal-path audit;
local build paths cannot be shipped in binaries or debug data.
The Wine and FreeType recipes explicitly target macOS 13.0, matching the app and
wrapper floor even when the developer runs a newer SDK. Native checks inspect
every Mach-O's architecture and deployment metadata before execution; a locally
built library that requires a newer macOS cannot qualify for publication.
See [RELEASE](RELEASE.md) for local storage configuration and the unpublished
build-input namespace. No generated binaries enter Git.

[build-freetype.sh](../scripts/build-runtime/build-freetype.sh) builds the pinned,
SHA-256-verified FreeType source for x86_64. The engine includes its dylib and
license notices. It uses FreeType's internal gzip inflater; optional PNG,
Brotli, bzip2 and HarfBuzz integrations are not included. Homebrew supplies
native build tools, not a host-architecture font library for the target engine.

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
has not been demonstrated by this audit. The SPDX document inventories the
wrapper, Wine, winetricks and bundled FreeType; it is not evidence of a complete
transitive dependency audit.

Important limits visible in the code:

- Homebrew workflow steps install available native tools and print versions;
  only the newly source-built FreeType dependency enforces its archive checksum.
- The persistent key includes target architecture and recipe/dependency identity,
  but not the observed compiler version or a future applied patch set.
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

[build-runtime.yml](../.github/workflows/build-runtime.yml) assembles and executes
native probes on macOS, then transfers explicit archives/metadata to Linux for
manifest signing and upload to the single configured production bucket.
[validate-publication.py](../scripts/build-runtime/validate-publication.py)
rechecks source/run identity, SHA-256 and size before signing transferred bytes.
The temporary assembly artifact expires after one day; final evidence after 30.
Only the developer's local engine build needs the Wine compiler dependencies;
assembly needs the storage client and tools supplied by the macOS image. The engine
workflow likewise publishes from Linux after a native receipt binds the local
archive/metadata to the validating workflow run. Producer metadata retains
`local-pre-push` and its outgoing source revision; it is not relabeled as a
GitHub-compiled binary. Manifest
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

| Location                              | Ownership and use                                                                                           |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `Wrappers/PortsideBaseline.app`       | Replaceable active runtime wrapper.                                                                         |
| `Prefixes/PortsideBaseline`           | Persistent user Wine prefix, Windows registry, Steam installation and account/game data. Preserve it.       |
| `Runtime/Pending`                     | Downloaded update archives and local pending index.                                                         |
| `Runtime/rollback-<time>-<UUID>`      | Prior wrapper; successful installation/startup retention keeps the newest one.                              |
| `Runtime/failed-<time>-<UUID>`        | Failed replacement retained for bounded recovery diagnostics; only the newest one is kept.                  |
| `Cache/Downloads`, legacy `Downloads` | Re-creatable artifacts; direct non-symlink entries expire after 24 hours once the active wrapper validates. |
| `Cache/XDG`                           | Runtime-tool cache.                                                                                         |
| `Manifests`                           | Cached manifest and ETag.                                                                                   |
| `SteamLibrary`                        | Created application directory and scan root; source does not establish that Steam installs games here.      |
| `Logs`, `Diagnostics`, `Profiles`     | Local operational state; inspect only with appropriate sanitization.                                        |

[PortsideRuntimeInstaller](../apps/desktop/Sources/PortsideCore/PortsideRuntimePipeline.swift)
extracts archives into a temporary cache directory, combines components under
`Contents/SharedSupport`, and changes engine `share-wine` into `share/wine`.
It applies the baseline and moves the previous wrapper into a rollback folder
before moving the candidate into place. The installed wrapper's
`Contents/SharedSupport/prefix` symlinks to the persistent managed prefix.
Existing managed prefixes are reused; new ones use `wineboot -u` through the
host. During that subprocess only, `mscoree`/`mshtml` registration is deferred:
without bundled Mono/Gecko, Wine would display optional-addon dialogs before
finishing WoW64 initialization. No DLL override is written to the prefix or
applied to Steam/game launches. Mono/.NET and Gecko-dependent applications still
need separate component installation and acceptance; Steam bootstrap does not
claim those capabilities. The official Steam verb runs as `--winetricks -q steam`
so Valve's installer uses its supported silent mode, with normal checksums and
no extra Steam launch flags.
Source does not establish migration of arbitrary legacy in-wrapper or
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
directories older than 24 hours are removed. Direct files and directories in
the current and legacy download caches also expire after 24 hours. Symlinks,
unrelated names, the managed prefix and game libraries are excluded. This bounds
future accumulation without treating user-owned Steam data as disposable cache.

The Steam flow installs the `steam` verb, launches the wrapper for the initial
updater cycle and launches it again for interactive use. Subsequent desktop
startup performs app/runtime checks and offers Open Steam. The detached wrapper
and Agent permit activity after the primary UI closes. Lease/handoff logic
serializes foreground bootstrap and the Agent's update worker; see
[UPDATE_ARCHITECTURE.md](UPDATE_ARCHITECTURE.md). These process relationships
are implemented; real interactive continuity remains a separate GUI test.

New wrappers advertise `launchDiagnosticsVersion: 1`. The desktop passes a fresh
`--launch-id <UUID>` only to those hosts; older hosts receive no new flags. The
host consumes this argument and atomically writes a per-launch JSON receipt in
`Logs/RuntimeLaunches/<UUID>.json` outside the prefix. It reports running,
execution failure or termination with the child PID, status, `exit` versus
`uncaughtSignal`, signal number and monotonic duration. Command diagnostics use
fixed executable labels and redact arbitrary arguments. Captured child output
is bounded to 64 KiB and sanitized. Dispatch read events and process termination
notifications replace polling. After the terminal receipt, collection ends at
EOF or a two-second grace deadline. The inherited socket uses `SO_NOSIGPIPE`:
later writes fail with `EPIPE`, without signalling a detached Steam process.
Output after this deadline is intentionally not collected. Receipt maintenance
retains 100 historical UUID JSON files for at most seven days; the current UUID
and files younger than five minutes are protected for concurrent readiness
readers. Symlinks, directories and non-receipt files are excluded. The separate
host text log still has no rotation.

Readiness checks the receipt and the LaunchServices application lifetime, the
wrapper and canonical external prefix, descendants and file-backed ownership.
It does not adopt unrelated newly observed Wine processes. After a terminal
launch and one second with no managed runtime children, it returns a process
failure instead of waiting for the 90-second graphical deadline. Execution
failure, signal, nonzero exit, no Steam process, Steam closing before readiness,
running without a window, and a window without webhelper have separate errors.
Only a currently detected window with webhelper yields `visibleButUnverified`;
this is still not evidence of rendered interaction.

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
also supports legacy second timestamps and UUID names. When an archive preserved
an invalid epoch modification date, selection falls back to the filesystem
attribute-change date. The failed destination is now uniquely timestamped rather
than using a literal placeholder. Crash journaling and a fully transactional
prefix/layout transition are still not established, so reliable end-to-end
recovery remains unverified.

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
