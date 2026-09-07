# Architectural decisions

These are decisions evidenced by current code or local Git history, not claims
of operational success. Dates are approximate commit periods (timezone can shift
a day). [STATUS](STATUS.md) owns validation evidence. Revisit a decision explicitly,
record its replacement and update related docs; do not silently restore old behavior.

## D13 — Use x86_64 Wine/WoW64 for Windows Steam on Apple silicon

- **Date:** 2026-09-07 UTC, first-launch investigation of app 0.1.28/runtime 0.1.26.
- **Status:** Adopted in source; complete signed Steam acceptance remains separate.
- **Decision:** Keep the native Swift host and build tools, but compile the Darwin
  Wine engine and bundled FreeType for x86_64, using Rosetta on Apple silicon.
  Reject an arm64 engine target for this source recipe. Bind persistent engine
  selection to target architecture and recipe/dependency hash, and require real
  x64 and x86 Windows execution in disposable prefixes before packaging and
  after archive extraction.
- **Reason:** The tracked Darwin loader has a low-address, 4 KiB layout that
  receives SIGKILL when compiled arm64 on the tested macOS, including with valid
  Developer ID signing. WoW64 PE outputs alone do not supply a native arm64 CPU
  emulator for Windows x86 Steam. `wine --version` avoids the failing re-exec.
- **Consequences:** Existing arm64 engine keys cannot satisfy the new recipe.
  Native arm64 Wine would need a separately validated loader/emulation design;
  signing exceptions or security-policy changes cannot substitute for it.
  [Evidence and limits](STEAM_FIRST_LAUNCH_FIX.md).

## D1 — Portside produces the runtime from tracked sources

- **Date:** August 2026, commit `ea7fdab`.
- **Status:** Confirmed.
- **Context:** Historical integrations referenced precompiled upstream wrappers/engines.
- **Decision:** Produce Portside wrapper/host, Wine and winetricks artifacts from
  Portside source and locked snapshots. Forbid commercial Sikarugir binary fallback.
- **Reason:** Keep source identity, licenses, checksums and build provenance under
  Portside's release process and avoid upstream release availability as a runtime dependency.
- **Consequences:** `vendor/` is audited input, never a hand-edited repair area.
  Toolchain or engine absence fails assembly; snapshots are not proof of a build.
- **Relevant files:** [lock](../upstream/lock.json),
  [build.sh](../scripts/build-runtime/build.sh),
  [production policy](../scripts/validate-production-policy.sh),
  [RUNTIME](RUNTIME.md).

## D2 — Valve supplies Steam; Portside owns the wrapper

- **Date:** August 2026; confirmed in current source.
- **Status:** Confirmed.
- **Context:** Portside prepares a Windows compatibility environment, not a Steam distribution.
- **Decision:** Install Steam using the vendored winetricks `steam` verb; do not bundle
  Steam/games or copy a native macOS Steam session. Rosetta comes from Apple.
- **Reason:** Preserve product/source boundaries and isolate the user's managed environment.
- **Consequences:** Fresh setup depends on Valve/Apple availability; Portside storage
  availability alone cannot prove clean installation. No DRM/anti-cheat bypass.
- **Relevant files:** [host](../apps/runtime-host/Sources/PortsideRuntimeHost/main.swift),
  [runtime pipeline](../apps/desktop/Sources/PortsideCore/PortsideRuntimePipeline.swift),
  [Rosetta manager](../apps/desktop/Sources/PortsideCore/RuntimePipeline.swift).

## D3 — App and runtime updates have separate trust roots

- **Date:** August 2026, commit `1bcd109`; startup ordering extended in `3eb02cc`.
- **Status:** Confirmed.
- **Context:** The signed macOS bundle and mutable per-user Wine environment have different lifetimes.
- **Decision:** Use Sparkle for app replacement and a separately signed Ed25519
  manifest for runtime components; license tokens use another key purpose.
- **Reason:** Permit independent runtime updates without mutating the signed app.
- **Consequences:** Appcast archive signatures, runtime signatures and minimum-app
  policy are different contracts. Private signing keys stay outside the app.
- **Relevant files:** [package](../apps/desktop/Package.swift),
  [update coordinator](../apps/desktop/Sources/Portside/PortsideUpdateCoordinator.swift),
  [manifest/license verifier](../apps/desktop/Sources/PortsideCore/CommercialInfrastructure.swift),
  [RELEASE](RELEASE.md).

## D4 — Production-only operation supersedes intermediate promotion

- **Date:** August 20–21, 2026, commit `11a71ad`.
- **Status:** Confirmed; former staging-before-production/manual storage promotion is superseded.
- **Context:** Older documentation and database history contain intermediate channels.
- **Decision:** Current app/runtime scripts and API expose production only; remove
  the intermediate promotion script. Local development is not a staging release channel.
- **Reason:** Remove the intermediate release step; no broader rationale is recorded.
- **Consequences:** No current staging build/promotion command exists. Legacy
  database rows are preserved by the notice-only migration, not converted/deleted.
  Isolated updater acceptance needs an explicitly authorized fixture arrangement.
- **Relevant files:** [migration](../apps/backend/prisma/migrations/20260821030000_production_only_channels/migration.sql),
  [schema](../apps/backend/prisma/schema.prisma),
  [release builder](../scripts/build_release.sh), [RELEASE](RELEASE.md).

## D5 — Persist Wine engines separately from runtime assembly

- **Date:** August 2026, commit `d8eca73`.
- **Status:** Confirmed.
- **Context:** Wine compilation is costly; wrapper/winetricks changes need not recompile it.
- **Decision:** Engine workflow produces a persistent component; runtime assembly
  fetches the engine matching the Wine lock and repackages it.
- **Reason:** Avoid redundant Wine builds and retain source-bound engine metadata.
- **Consequences:** Source/metadata/hash/size mismatch blocks assembly. Current key
  design omits toolchain/architecture/patch identity, and ordinary uploads do not
  enforce immutability; these are limitations, not confirmed guarantees.
- **Relevant files:** [engine workflow](../.github/workflows/build-engine.yml),
  [runtime workflow](../.github/workflows/build-runtime.yml),
  [resolver](../scripts/build-runtime/resolve-engine.sh),
  [fetcher](../scripts/build-runtime/fetch-engine.sh).

## D6 — One active artifact bucket

- **Date:** September 2026, commit `1ce78b2`.
- **Status:** Confirmed.
- **Context:** Earlier configuration and guides described dual publication/failover.
- **Decision:** Use one configured S3-compatible bucket and API-generated temporary
  download redirects.
- **Reason:** The commit removes the secondary artifact-storage path.
- **Consequences:** No second active target or automatic failover. Bucket policy,
  backups, object retention and availability need external evidence.
- **Relevant files:** [backend config](../apps/backend/src/core/app-config.ts),
  [artifact service](../apps/backend/src/modules/artifacts/artifact.service.ts),
  [publisher](../scripts/publish_release.sh), [RAILWAY_DEPLOYMENT](RAILWAY_DEPLOYMENT.md).

## D7 — Existing workflows automatically release qualifying main changes

- **Date:** September 2026, commit `9d60807`.
- **Status:** Confirmed implementation; external execution/protection is Unknown.
- **Context:** App release previously required dispatch; source/runtime publication also has automation.
- **Decision:** Qualifying successful CI on main may trigger the production app
  workflow; dispatch remains available.
- **Reason:** The recorded change automates release production after its configured checks.
- **Consequences:** Current CI does not run the full test matrix or enforce GUI
  acceptance. Environment reviewer rules are external. This does not authorize
  future agents to trigger publication or promotion without an explicit task request.
- **Relevant files:** [release workflow](../.github/workflows/release-production.yml),
  [CI](../.github/workflows/ci.yml), [agent authority](../AGENTS.md).

## D8 — Preserve managed user data across runtime replacement

- **Date:** August 2026; confirmed in current runtime installer.
- **Status:** Confirmed design intent; recovery completeness is unvalidated.
- **Context:** Wrappers/engines change while Steam registry, account state, games and saves belong to the user.
- **Decision:** Use a persistent managed prefix outside replaceable wrappers,
  linked into the wrapper; never delete user data to fix runtime or license failure.
- **Reason:** Separate updateable assets from persistent user state.
- **Consequences:** No automatic copying of native Steam data or whole libraries.
  Rename-based installation, rollback selection and Wine prefix changes still
  require failure/preservation validation; `SteamLibrary` is not an automatically
  configured Steam install location.
- **Relevant files:** [paths](../apps/desktop/Sources/PortsideCore/PortsideCore.swift),
  [installer](../apps/desktop/Sources/PortsideCore/PortsideRuntimePipeline.swift),
  [RUNTIME](RUNTIME.md).

## D9 — Runtime downgrade needs authenticated authorization

- **Date:** August 2026; confirmed in current client.
- **Status:** Confirmed client rule; backend/local recovery gaps remain.
- **Context:** Replaying an older valid manifest must not silently downgrade a client.
- **Decision:** Compare accepted manifest versions and require signed rollback
  authorization matching the previous version; retain signed minimum-app policy offline.
- **Reason:** Keep recovery inside the signed trust contract.
- **Consequences:** Republishing an old payload alone may fail client checks.
  Backend superseded-target preconditions and local rollback defects prevent a
  guaranteed end-to-end rollback claim.
- **Relevant files:** [backend client](../apps/desktop/Sources/PortsideCore/PortsideBackendClient.swift),
  [runtime service](../apps/backend/src/modules/runtime/runtime.service.ts),
  [ROLLBACK](ROLLBACK.md), [SECURITY](SECURITY.md).

## D10 — Commercial startup installs into Applications before updates/runtime

- **Date:** September 2026, commit `3eb02cc`.
- **Status:** Confirmed; supersedes direct-DMG setup in `50af4e1` and installer update deferral in `a09aae7`.
- **Context:** DMG/translocated execution and overlapping app/runtime installation complicate safe replacement.
- **Decision:** Require writable, non-translocated `/Applications/Portside.app`;
  validate identity/version during relocation and await Sparkle preflight before
  license/state/runtime/Steam work.
- **Reason:** Establish the installed application and update outcome before bootstrap.
- **Consequences:** Developer/Debug exemptions remain explicit; initial preflight blocks
  known-critical or unresolved installer outcomes before runtime work. Later
  scheduled Sparkle cycles need separate integration evidence. Real privilege prompts and complete
  update/relaunch still require manual acceptance.
- **Relevant files:** [installation transaction](../apps/desktop/Sources/PortsideCore/ApplicationInstallationTransaction.swift),
  [bootstrap](../apps/desktop/Sources/PortsideCore/PortsideBootstrap.swift),
  [preflight](../apps/desktop/Sources/PortsideCore/PortsideAppUpdatePreflight.swift).

## D11 — Keep product UI in English

- **Date:** Native release metadata/current source, reinforced by the September 2026 documentation task.
- **Status:** Confirmed policy; not universally satisfied by existing landing copy.
- **Context:** Portside's native bundle and newly added startup/installation messages use English.
- **Decision:** Keep all Portside UI and new documentation in English.
- **Reason:** Preserve a consistent product language and agent context.
- **Consequences:** Release validation checks English development region; that is
  not a full copy audit. Existing Portuguese landing content is a documented gap,
  left unchanged by this documentation-only task.
- **Relevant files:** [app plist](../apps/desktop/Resources/Info.plist),
  [bundle validation](../scripts/validate_release_bundle.sh),
  [landing routes](../apps/landing/src/routes), [AGENTS](../AGENTS.md).

## D12 — Bound replaceable local storage without pruning user data

- **Date:** September 6, 2026.
- **Status:** Confirmed implementation; real accumulated-data cleanup is not end-to-end validated.
- **Context:** Runtime replacement previously retained every rollback indefinitely,
  and interrupted extraction could leave large temporary directories. Older
  releases could also leave multiple prefix recovery points.
- **Decision:** After validating the active wrapper, run storage maintenance on
  startup and after successful installation. Retain one runtime rollback, one
  failed wrapper and one legacy prefix recovery point; remove abandoned staging
  directories and direct entries in Portside-owned download caches after 24
  hours. Accept current millisecond and legacy second history timestamps, falling
  back to filesystem attribute dates when archived modification dates are invalid.
- **Reason:** Bound replaceable disk usage while preserving a recovery path.
- **Consequences:** The active managed prefix, Steam credentials, games, saves and
  libraries are never cleanup candidates. Cleanup is best effort, accepts only
  direct non-symlink entries in owned locations, and cleanup failures do not block
  startup. Downloaded artifacts may need to be fetched again after expiration.
- **Relevant files:**
  [maintenance](../apps/desktop/Sources/PortsideCore/PortsideStorageMaintenance.swift),
  [runtime installer](../apps/desktop/Sources/PortsideCore/PortsideRuntimePipeline.swift),
  [RUNTIME](RUNTIME.md).

## D13 — Bind app publication to runtime assembly of the tested commit

- **Date:** September 7, 2026.
- **Status:** Implemented and locally tested; GitHub execution remains unvalidated.
- **Decision:** App publication waits for successful runtime assembly of its
  `target_sha`, then checks provenance, wrapper source commit, workflow build ID
  and signed/unsigned manifest agreement. App-only changes assemble a new wrapper
  and reuse the recipe-selected persistent engine; they do not rebuild Wine.
- **Reason:** CI can finish before a new engine, so selecting the latest older
  runtime could publish a new app with the original defective engine.
- **Consequences:** Missing, failed, cancelled or expired matching evidence blocks
  release. Completion events recheck prerequisites once on Linux; no runner waits
  for another workflow. The macOS job starts only when both are ready. Existing
  production publication triggers remain; this change authorizes no agent push,
  dispatch or promotion. See [RELEASE](RELEASE.md).

## D14 — Defer optional Wine addons during Steam prefix bootstrap

- **Date:** September 7, 2026.
- **Status:** Verified for local prefix creation and official Steam installation;
  final distribution and graphical Steam acceptance remain unvalidated.
- **Decision:** Only `--create-prefix` temporarily excludes `mscoree`/`mshtml`
  registration, deferring optional Mono/Gecko installers. Steam/game subprocesses
  receive normal DLL loading; no registry DLL override is written. Install Steam
  through the official `winetricks -q steam` verb and its pinned checksums.
- **Reason:** Wine's addon registration opens a modal installer before WoW64 files
  finish initialization. Interrupting that bootstrap leaves a partial prefix;
  subsequently starting Valve's PE32 installer can fail to load `kernel32.dll`.
- **Consequences:** This baseline prepares Steam without addon dialogs. It does
  not claim Mono/.NET or Gecko availability; applications needing them require
  separate component installation and acceptance. The production-host bootstrap
  probe exercises the same policy, without test-only overrides. See
  [the investigation](STEAM_FIRST_LAUNCH_FIX.md) and [RUNTIME](RUNTIME.md).

## D15 — Allocate runners only for ready work and keep portable publication on Linux

- **Date:** September 7, 2026.
- **Status:** Implemented but not end-to-end validated; local regression/static checks only.
- **Decision:** CI and runtime completion each recheck the same-commit release
  prerequisites once. Serialize app releases and suppress duplicate automatic
  publication for a source already uploaded. Keep native compilation/execution
  on macOS, then verify transferred archive hashes/source/run identity and sign
  the runtime manifest/publish engine and runtime on Linux. Use local hooks for
  early lint/test feedback while retaining independent remote trust gates.
- **Reason:** The former five-hour Linux polling job occupied a runner while
  another runner compiled Wine. Portable publication and unused compiler tools
  unnecessarily extended native jobs; whole build-directory uploads retained
  temporary compiler and extraction trees.
- **Consequences:** Dependency waits consume no allocated runner. Failed/missing
  prerequisites never select an older runtime; manual recovery must still meet
  both gates. A cold native build remains necessary and Apple notarization still
  waits within its native job. No new production destination or app-change
  trigger is introduced. See [RELEASE](RELEASE.md) and [TESTING](TESTING.md).
