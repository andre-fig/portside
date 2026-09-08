# Installation and startup update validation

**Evidence scope:** the protocol below describes implementation and required manual
checks. The task report is a historical account from a prior session, not a result
of the 2026-09-05 documentation audit. Its ignored artifacts, installed apps and
external receipts were not re-inspected. Consult [STATUS](STATUS.md) for current
audit evidence and [TESTING](TESTING.md) for the full matrix.

Commercial bundles use `PortsideBuildChannel=production` and must run from the
writable, non-translocated `/Applications/Portside.app`. The development script
explicitly uses `development`; Debug always logs an English exemption.

The in-memory bootstrap transitions are:

```text
checkingInstallationLocation → checkingAppUpdate
    → installingAppUpdate → relaunching → [new process]
    → checkingRuntime → installingRuntime → checkingSteam
    → launchingSteam → ready
```

An invalid location enters `movingToApplications` only after the move button is
clicked. A failure enters `failed`. Repeated callbacks cannot claim an already
started stage. The runtime installer, Steam setup and launcher are guarded by the
completed app preflight. License validation and loading/recovering environment
state also occur after that gate. A shared advisory lease serializes foreground
bootstrap with background runtime preparation; the OS releases it on process
exit. Legacy runtime-only workers are identified by owner, exact arguments and
Developer ID identity before they are stopped; compatibility/Steam processes
are not part of that handoff.

The installer validates Developer ID signatures, bundle identity, publisher and
both version values. It copies with `ditto --rsrc --extattr --acl`, validates the
staged copy, requires Gatekeeper execution approval, releases only that private
copy's quarantine attributes, revalidates its signature, and atomically exchanges
an older installation. See [the reopen regression report](INSTALLATION_REOPEN_FIX.md)
for the 0.1.24 translocation failure and scoped verification. Previous bundles
are retained under `/Applications/.Portside-Previous-<UUID>.app`. An absent target
is installed with an exclusive rename. Authorization is requested only after a
permission failure; privileged code runs from a verified private copy. The new
instance must be reported open by LaunchServices before the old app terminates.
An installed helper then attempts non-forced DMG ejection after the old PID exits.
If App Translocation prevents proving the original disk-image mount, ejection is
omitted; installation and relaunch still work without guessing another volume.

Sparkle first performs an immediate information probe, independent of runtime,
Steam, existing state and preferences for future scheduled checks. The probe's
20-second timeout can release a valid build; late probe callbacks cannot install
an update. An offered update enters an awaited installation session. Normal
updates follow the existing automatic-download preference; critical updates
remain blocking and use Sparkle's standard progress UI. Confirmation and macOS
authorization remain standard Sparkle UI. A 10-minute installation deadline
blocks instead of racing a still-active installer.

Only a source/expected-version receipt survives relaunch. `CFBundleVersion` is
compared using Sparkle's version comparator. Failed relaunches need an explicit
retry; a retry cannot erase the expected-version requirement when offline or
when the feed offers no replacement. Separately, a signed runtime manifest's
minimum app version remains mandatory across cached/offline checks.

## Repeatable automated checks

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
swift test --package-path apps/runtime-host
./scripts/validate-production-policy.sh
git diff --check
```

Tests use disposable filesystem fixtures and mocked authorization/LaunchServices.
The runtime-host suite also executes its compiled host inside a relocated fixture
bundle from an unrelated working directory, with a disposable home and dummy Wine.
This tests bundle discovery, not Steam or graphical readiness.

## Required real acceptance

Use a dedicated macOS test account with no existing Portside runtime, prefix,
Steam library or commercial license. Do not clean an everyday account to create
a first-launch scenario.

1. Build a release with approved public configuration; sign all nested code and
   the main bundle with Developer ID; notarize and staple the app and DMG.
2. Verify `codesign --verify --deep --strict`, `stapler validate`, `spctl`, the
   final app and helper Info.plists, and installed Sparkle load commands.
3. Open the DMG app and verify the English move gate is visible. No runtime,
   license recovery, Steam setup or appcast request should have started.
4. Click **Install and Open**. Verify progress through installation and opening,
   the installed path, valid
   signature, new process, original process exit and best-effort DMG ejection.
5. Confirm `app_update_check_started trigger=launch mode=immediate_probe` before
   `app_update_preflight_finished` and before runtime checking/download logs.
6. Repeat in a fresh test account without a runtime or Steam. A no-update check
   must finish without an extra updater confirmation screen.
7. Configure an explicitly authorized isolated fixture feed and signing key before
   publishing any fixture. Do not replace the production appcast for testing. No supported staging
   product channel exists; the fixture arrangement needs separate authorization.
8. Offer a higher build, first normal automatic and then critical. Confirm archive
   download, Sparkle signature verification, installation, relaunch, expected
   version verification and only then runtime installation.
9. Confirm real rendered Steam login and keyboard/mouse interaction after the
   complete flow, following `VALIDATION.md`. Portside must keep its verification
   screen open after window/webhelper detection; confirm **Steam is usable** only
   after actual interaction. **The window is blank** and fresh exhausted GPU
   initialization failures must retain a recoverable error instead of completing
   graphical handoff. Old or recovered log failures must not block this session.
10. Exercise permission denial, newer installed build, interrupted update,
    offline feed, timeout and signed minimum-version block. Keep previous apps
    and all runtime/prefix/game data intact.

## Historical evidence for the prior implementation session

See the task report at the end of this file. The prior report placed generated artifacts and logs
under ignored `build/bootstrap-validation/`; they are not published.

### Task report — 2026-09-04 local session / 2026-09-05 UTC

The prior session reported implementation complete in its working tree; no commit, push, appcast
publication or production release was performed.

| Area                                   | Evidence                                                                                                                                                                                               | Result                                                                                                 |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| Desktop tests                          | `evidence/desktop-tests.log`: 111 discovered, 110 passed, the real probe skipped by default                                                                                                            | Passed                                                                                                 |
| Real installed Sparkle probe           | Explicit opt-in subsequently passed with real Sparkle 2.9.6 and the current HTTPS production appcast; information probe only, installation and scheduling technically refused by the adapter           | Passed; not an update-install/relaunch test                                                            |
| Runtime host                           | Five tests, including the compiled host in a relocated disposable bundle, unrelated cwd and dummy Wine                                                                                                 | Passed; not Steam validation                                                                           |
| Builds and source checks               | Debug build, Release build, production policy, shell syntax, plist lint and diff whitespace                                                                                                            | Passed                                                                                                 |
| Candidate signing                      | Developer ID, nested Sparkle/agent/installer and outer app, strict deep verification before/after installation                                                                                         | Passed                                                                                                 |
| Apple notarization                     | Candidate ZIP submission `d9e43b0d-9e3f-4dd4-9919-3a43fa115462` accepted; candidate app and DMG stapled/validated; installed app accepted by Gatekeeper                                                | Passed                                                                                                 |
| Candidate DMG gate                     | Real signed/notarized `0.1.24` DMG launched; English move gate inspected through the macOS Accessibility window tree; no bootstrap continuation                                                        | Passed for the native gate; pixel screenshot capture was unavailable                                   |
| Move button, reopen, exit and ejection | Real signed/notarized **fault fixture** `0.1.23`, with deliberately invalid Sparkle public-key configuration, copied to `/Applications`; new installed PID observed, source exited, source DMG ejected | Passed for relocation; child deliberately blocked before license/state/runtime access                  |
| Signed older replacement               | Actual installer then atomically replaced that older fixture with correct candidate `0.1.24`, retaining the fixture as a previous bundle; strict signature and staple checks passed                    | Passed; no pre-existing user app was replaced                                                          |
| Immediate appcast query                | Installed-bundle probe logged `app_update_check_started` at `2026-09-05T01:09:17Z`, then `result=no_update bootstrap_allowed=true` at `01:09:18Z`                                                      | Passed in the isolated updater harness, separate from full bootstrap                                   |
| Bundle paths and language              | No reference to this development checkout in the three Portside executables; installed loader uses `@rpath/Sparkle.framework`; English app metadata and new UI/error strings                           | Passed; precompiled Sentry still contains its upstream CI source filenames, which are not lookup paths |
| Complete runtime assembly              | Source audit and changed wrapper compilation passed; fetching persistent engine stopped because `PORTSIDE_PUBLIC_BUCKET`/storage configuration was absent                                              | Not completed                                                                                          |
| First clean runtime/Steam setup        | A disposable clean account was unavailable; existing user state was preserved                                                                                                                          | Requires a disposable test account                                                                     |
| Real normal/critical isolated update   | No isolated fixture feed/authorized publication target was supplied or configured; repository environments were production only                                                                        | Not performed                                                                                          |
| Steam rendered window and interaction  | No Steam launch or login interaction performed in this task                                                                                                                                            | Not proven                                                                                             |
| Administrator authorization UI         | Permission/error paths and protected-copy transaction tested automatically; this real move needed no administrator prompt                                                                              | Real prompt/denial remains unproven                                                                    |

At the end of that prior session, the report recorded the candidate installed at `/Applications/Portside.app` and
not running. The previous retained app was that session's deliberately blocked test
fixture, not a user's prior installation. The prior report states that no runtime, prefix, Steam library,
installed game, license token or private key was removed or replaced.

Generated candidate artifacts:

- `build/bootstrap-validation/candidate/Portside-0.1.24.dmg`
- `build/bootstrap-validation/candidate/Portside-0.1.24-notarized.zip`
- `build/bootstrap-validation/candidate/checksums.txt`

The prior report placed logs, public metadata, Accessibility transcripts and move/replacement
results under `build/bootstrap-validation/evidence/`. The fault fixture is
under `build/bootstrap-validation/move-fixture/` and must not be distributed.
The prior report described the candidate as locally validated, not published.
Its present availability and installed state were not checked in this audit.
