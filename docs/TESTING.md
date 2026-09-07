# Testing and evidence

A check proves its observed behavior only. Use these operational states:

| State                                    | Meaning                                                                      |
| ---------------------------------------- | ---------------------------------------------------------------------------- |
| Verified                                 | A stated check/result was observed; include date/commit and scope            |
| Implemented but not end-to-end validated | Code or automation exists, but the full operational path lacks evidence      |
| Planned                                  | Requirement/design exists without complete implementation                    |
| Blocked                                  | A concrete missing prerequisite or implementation gap prevents the milestone |
| Unknown                                  | Available evidence cannot establish current state                            |

[STATUS](STATUS.md) owns results from this audit. Historical results in
[BOOTSTRAP_VALIDATION](BOOTSTRAP_VALIDATION.md) are not new executions.

The [0.1.28 first-launch follow-up](STEAM_FIRST_LAUNCH_FIX.md) adds actual-host
tests for immediate exit, SIGKILL, exec failure, redaction and inherited output,
and desktop readiness tests for early termination, detached children, unrelated
Wine, canonical prefix ownership and missing window/webhelper. The engine build
now runs `scripts/build-runtime/validate-engine-execution.py` before packaging;
layout validation repeats it after extraction. It executes x64 and x86 Windows
commands in a fresh symlinked prefix, with cleanup restricted to that fixture.
`scripts/build-runtime/test-loader-layout.py` independently compares minimal
Darwin loader layouts, optionally with Developer ID. These checks still do not
establish graphical Steam acceptance or final distribution signing.

The release binding tests run with
`python3 -B -m unittest discover -s scripts/tests -v` and are included in CI's
production source policy job. They cover pending/failed/cancelled runtime builds,
skipped engine-dependent assembly, expired artifacts, wrong source/run provenance
and disagreeing manifests. They also cover both completion orders, duplicate
publication suppression, separate native/Linux runtime jobs, archive corruption,
wrong workflow/source evidence, symlinks and local hook selection/index behavior.
Local producer tests additionally reject missing native CI receipts, mismatched
recipe/source inputs and changed metadata after validation. They check that
ordinary pushes need no transfer configuration and missing configuration fails
before compilation. Provider tests reject a Railway API from another repository/environment and
prevent partial environment values from mixing with provider credentials.
Safe tar extraction tests require `tarfile.data_filter`; use Python 3.12+ locally
for the full suite (the native CI job pins Python 3.12).
`actionlint .github/workflows/*.yml` checks wiring;
no workflow dispatch is required for these local checks.

Extracted-layout validation also invokes
`python3 scripts/build-runtime/validate-steam-bootstrap.py WRAPPER ENGINE WINETRICKS`.
This uses a fresh wrapper/home/symlinked prefix and the actual host, without
test-only DLL overrides; both system32 and syswow64 kernel32 must exist and both
Windows commands must return their expected nonzero statuses. Paths must refer
to an unassembled build wrapper, installed-layout engine and winetricks source
root. Adding `--install-steam` downloads and verifies Valve's installer via the
official quiet winetricks verb. Adding `--observe-steam` then opens Steam without
flags for a 120-second manual observation interval. Neither installation nor
the observation timer proves a rendered, interactive window. Cleanup only stops
the newly-created fixture's Wine server and removes that temporary fixture.

## Automated check matrix

Commands run from the repository root unless the row names another directory.
Dependency installs and builds write generated output. Do not run them when the
task forbids those writes; this documentation audit used read-only/static checks.

| Component / command                                                                                                          | Type                                            | Environment / external dependencies                                                       | Validates                                                                                           | Limits / audit status                                                                                                                       |
| ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `swift test --package-path apps/desktop`                                                                                     | XCTest, mocks and disposable fixtures           | macOS, Swift 6; resolved Sparkle/Sentry artifacts                                         | Core trust/download/installation/bootstrap, app updater adapters, leases and compatibility policies | Implemented but not end-to-end validated; not rerun. Real installed Sparkle probe is opt-in and may contact the feed                        |
| `swift build --package-path apps/desktop`                                                                                    | Compilation                                     | Same; SwiftPM may download dependencies                                                   | Four desktop products compile                                                                       | Unknown current build result; not rerun; no signature/UI proof                                                                              |
| `swift test --package-path apps/runtime-host`                                                                                | XCTest and compiled dummy-host process          | macOS, Swift 6; no package dependencies                                                   | Relocated wrapper resolution with dummy Wine/disposable home                                        | Implemented but not end-to-end validated; not rerun; no Steam                                                                               |
| `swift build --package-path apps/runtime-host`                                                                               | Compilation                                     | macOS/Swift                                                                               | Host compiles                                                                                       | Unknown current build result; not rerun                                                                                                     |
| `npm ci`, then `npm run prisma:validate`, `npm run typecheck`, `npm run lint`, `npm test`, `npm run build` in `apps/backend` | Schema, static checks, Vitest, TypeScript build | Node 22/npm; registry for install, DATABASE_URL schema configuration; specs mock services | DTO/controller/service contracts, source policy, license behavior, storage URL handling             | Implemented but not end-to-end validated; not rerun. Build prehook generates Prisma client; mocks do not exercise live PostgreSQL/S3/GitHub |
| `bun install --frozen-lockfile`, then `bun run lint`, `bun run typecheck`, `bun run build` in `apps/landing`                 | Static checks and server/client build           | Bun per workflow; package registry for install                                            | TS/React and build integration                                                                      | Implemented but not end-to-end validated; not rerun. No landing unit-test script or Stripe fulfillment test exists                          |
| `./scripts/validate-production-policy.sh`                                                                                    | Source policy                                   | Git checkout, sh, rg, source snapshots                                                    | Forbidden production URLs/names, vendor layout and compiled-archive exclusions                      | Verified in audit; does not build Wine or hash every snapshot                                                                               |
| `./scripts/build-runtime/source-audit.sh`                                                                                    | Presence checks                                 | Local sources                                                                             | Required runtime build inputs exist                                                                 | Verified in audit; not an integrity/compilation test                                                                                        |
| `./scripts/build-runtime/resolve-engine.sh`                                                                                  | Identity derivation                             | jq and local lock/VERSION                                                                 | Current engine name/key derivation                                                                  | Verified in audit; does not prove object exists in storage                                                                                  |
| `./scripts/build-runtime/validate-manifest.sh docs/runtime-manifest.json` and backend fixture equivalent                     | Negative structural validation                  | jq/rg                                                                                     | Blocked empty fixtures are rejected                                                                 | Verified rejection in audit; no crypto verification and no runnable release manifest                                                        |
| `sh -n` for each tracked shell script/hook                                                                                   | Parsing                                         | POSIX shell                                                                               | Shell grammar only                                                                                  | Verified: 35 files; does not execute script bodies                                                                                          |
| `actionlint .github/workflows/*.yml`                                                                                         | Workflow lint                                   | Installed actionlint                                                                      | Workflow expression/schema/static checks                                                            | Verified in audit; no jobs/services executed                                                                                                |
| `git diff --check`                                                                                                           | Diff whitespace                                 | Git                                                                                       | Changed tracked text whitespace                                                                     | Verified after editing; untracked docs also checked with formatter/link scanner                                                             |

Test ownership: [desktop tests](../apps/desktop/Tests),
[host tests](../apps/runtime-host/Tests), [backend Vitest config](../apps/backend/vitest.config.ts)
and adjacent `*.spec.ts` files. Pure policy tests do not prove their wiring into
production: renderer fallback, remote profiles, runtime rollback and license
fulfillment need separate integration evidence.

## Artifact and manual acceptance matrix

Follow the linked runbook for required configuration; command names below are
existing repository scripts, not fully configured release invocations.
No publishing, Apple, GUI or storage step was executed during this audit.

| Component / command or procedure                                       | Type                                       | Environment / external dependencies                                                                                     | Required observation                                                                             | Current status / limitation                                                                                                                                 |
| ---------------------------------------------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `./scripts/package_app.sh`                                             | Local bundle                               | macOS/Xcode, resolved dependencies; optional Sentry upload when configured                                              | Correct app/helper layout and metadata                                                           | Implemented but not end-to-end validated in this audit; default ad hoc signature is not commercial                                                          |
| Engine build + runtime assembly in [RUNTIME](RUNTIME.md)               | Build/layout integration                   | macOS toolchain; Homebrew inputs for engine build; configured storage with the matching persistent engine for assembly  | Source-built Wine and three usable artifacts, source identity, SHA-256/size, SBOM/provenance     | Implemented but not end-to-end validated; no build executed                                                                                                 |
| `./scripts/generate_manifest.sh` plus backend publish/desktop verifier | Signing/negative trust tests               | External Ed25519 key, approved public key, backend and desktop                                                          | Accepted authentic manifest; reject unsigned, altered, wrong-key/channel/host/min-version inputs | Implemented but not end-to-end validated; structural shell validator alone is insufficient                                                                  |
| `./scripts/sign_release.sh`                                            | Code signing                               | Developer ID/Keychain and approved bundle                                                                               | Nested and outer codesign, Hardened Runtime entitlements, strict verification                    | Unknown current signing result; historical local report only                                                                                                |
| `./scripts/notarize_release.sh`                                        | Apple submission/staple                    | Apple credentials/service, signed bundle                                                                                | Accepted submission, stapled app/DMG, final ZIP containing stapled app                           | Unknown current result; ZIP itself is not stapled                                                                                                           |
| `./scripts/create_dmg.sh`, `./scripts/validate_release_bundle.sh`      | Packaging/mount validation                 | macOS disk-image tools and signed candidate                                                                             | Correct bundle and app-only DMG contents                                                         | Implemented but not end-to-end validated this audit                                                                                                         |
| Publish/register scripts in [RELEASE](RELEASE.md)                      | External integration                       | GitHub/one S3 bucket/API/PostgreSQL and authorization                                                                   | Stored object hash/size, backend source/build/release/manifest/appcast binding                   | Unknown current state; shell upload success is not graphical acceptance                                                                                     |
| [Bootstrap protocol](BOOTSTRAP_VALIDATION.md)                          | Manual app installation                    | Dedicated Mac account, signed/notarized app/DMG, permissions                                                            | Move gate, identity checks, replacement, reopen/eject, permission denial and no data loss        | Implemented but not end-to-end validated; historical partial evidence is scoped separately                                                                  |
| Sparkle normal and critical update protocol                            | Manual updater                             | Two authorized signed builds, feed, macOS/Apple services                                                                | Download/install/relaunch/version receipt, timeout/offline/min-version behavior                  | Implemented but not end-to-end validated; needs authorized fixture feed and two builds. No staging product channel exists; live production state is Unknown |
| `./scripts/validate-clean-install.sh`                                  | Operator-assisted runtime setup            | Newly allocated disposable root, authentic artifact, Apple silicon GUI, Valve/Apple, Accessibility/interactive Terminal | Prefix creation, updater exit, second Steam opening, rendered login and interaction              | Blocked by source-inferred nested prefix link in fixture assembly; script only checks nonempty signature, not crypto, and non-TTY exits before acceptance   |
| [Steam graphical acceptance](VALIDATION.md)                            | Manual                                     | Real display/test account/Valve                                                                                         | Usable rendered window and mouse/keyboard input, persistence after updater                       | Unknown; file, PID, Dock icon and window metadata are insufficient                                                                                          |
| GunZ control game; [Unturned fixture](UNturned_VALIDATION.md)          | Manual game play / code fixture separately | Authorized Steam account/download, actual game and GUI                                                                  | Install, launch, rendered usable scene and close; no anti-cheat bypass                           | Unknown playability; neither tests nor marketing establishes compatibility                                                                                  |
| [Runtime/app rollback](ROLLBACK.md)                                    | Failure/recovery integration               | Disposable data, previous authenticated artifacts, backend/operator                                                     | Usable previous runtime/fixed app, prefix/library/credentials intact                             | Blocked from a reliable end-to-end claim by documented rollback implementation gaps                                                                         |
| Prefix/game preservation across update, crash, repair and rollback     | Manual plus filesystem fixtures            | Disposable prefix/library with synthetic marker and saved state                                                         | Same user data after each scenario, with injected failures                                       | Implemented but not end-to-end validated; preservation evidence missing, see [RUNTIME](RUNTIME.md)                                                          |

## Hooks, CI and documentation checks

[pre-commit](../scripts/hooks/pre-commit.sh) checks the actual staged content:
whitespace, shell/JSON/Python syntax, and workflow lint. `actionlint` is required
when committing/pushing workflows; missing tools fail with setup guidance.
[pre-push](../scripts/hooks/pre-push.sh) selects checks from outgoing changed paths:

| Changed area | Local checks |
| --- | --- |
| Desktop, runtime host, wrapper template or wrapper build script | Both Swift suites and builds |
| Workflows or scripts | Release/publication/hook regression tests; workflow lint and shell/Python syntax when relevant |
| Engine inputs pushed to `main` | Build exact committed sources locally with compatible Wine cache; validate and upload unpublished input before Git sends the commit |
| Backend | Prisma schema, typecheck, lint, tests and build |
| Landing | Lint, typecheck and build |
| Runtime, application, backend, upstream, scripts or workflows | Production source policy |
| JSON | Parse changed existing files; deleted files do not fail the hook |

Enable the versioned hooks once per clone using `./scripts/install-git-hooks.sh`;
`git config --get core.hooksPath` should return `.githooks`. No commit or push is
needed to run `python3 -B -m unittest discover -s scripts/tests -v`: hook tests
use a disposable synthetic repository layout and fake commands, with no external
writes. Local hooks provide early feedback but can be bypassed; they do not
replace release trust checks.

Current [CI](../.github/workflows/ci.yml) retains production policy, these Python
regressions and backend schema/build on Linux. Swift tests, backend unit tests and
the whole local matrix are not GitHub release gates. Wine compilation happens
locally before engine-changing pushes. CI's native
engine job only checks extracted x64/x86 execution and has a ten-minute cap;
packaging, signing and notarization remain macOS jobs; completing a dependency
is handled by GitHub events/`needs`, without an allocated runner polling another
workflow. [RELEASE](RELEASE.md) describes exact ordering and remaining Apple wait.

No repository-wide Markdown linter/link checker is configured. Landing declares
Prettier. A read-only `node apps/landing/node_modules/prettier/bin/prettier.cjs --check`
with an explicit Markdown file list can check docs when already installed; do not
use `bun run format` for a docs audit because it writes across the landing tree.
This audit additionally checked local links/anchors, inline source references,
package-script names, forbidden paths and possible secrets without a network call.

When testing future changes, include negative signature/hash/size/host/path inputs,
offline and interrupted operations, app replacement identity/version checks, runtime
handoff races and unrelated process/data preservation. Record actual results and
missing GUI/certificate/service prerequisites in STATUS instead of promoting
implementation coverage into operational success.
