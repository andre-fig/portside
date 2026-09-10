# Audit status — 2026-09-05 UTC

This is a snapshot and can become stale. It is not a live deployment report.
Update it when a milestone changes, with commit, command/result and validation
scope; update [DECISIONS](DECISIONS.md) when architecture changes.

- **Audit date:** 2026-09-05 UTC; initial clock reading 01:51:44 UTC.
- **Audited commit:** `3eb02cca022eb8140fe29d11170213782a40f4c9`.
- **Before audit:** clean worktree, local branch `main`, status displayed
  `main...origin/main`. No fetch was performed; remote freshness is Unknown.
- **Scope:** repository-owned source/tests/docs/scripts/workflows/configuration and
  local Git history. Vendor source integrity was checked; generated dependencies,
  artifacts, installed applications and user data were not operational evidence.
- **Actions:** local documentation edits and non-destructive local checks only.
  No dependency installs/builds, GUI, credentials, service calls or publication.

## Automatic newer installed app follow-up — 2026-09-10 UTC

**Implemented but not end-to-end validated:** an older Portside copy launched
outside Applications now detects and opens the newer trusted installed copy
without requesting confirmation. If the installer discovers a newer version
while attempting replacement, it also revalidates and opens that installed copy.
No downgrade is performed. Both signature identities, publisher, release and
build ordering remain enforced. The old instance exits only after successful
opening; failures keep the retry UI and do not schedule disk-image ejection.

**Verified local checks:** `swift test --package-path apps/desktop` completed
168 tests, one optional signed-app probe skipped, zero failures. Fixtures cover
newer/equal/older versions, build ordering, invalid publisher/signature, a changed
destination, a newer version arriving during installation and failed reopening.
`swift build --package-path apps/desktop`, `./scripts/validate-production-policy.sh`
and `git diff --check` passed. No installed app was replaced or opened by these
checks; signed-DMG and actual LaunchServices handoff remain graphical acceptance
work. Prior local privacy/automatic-closure changes were preserved. No commit,
push or publication was performed.


## Automatic desktop closure follow-up — 2026-09-10 UTC

**Implemented but not end-to-end validated:** the owner requested removing the
customer-facing “The window is blank” / “Steam is usable” questionnaire. Fresh
setup and subsequent Steam launch now complete automatically after managed Steam,
webhelper and on-screen window detection, followed by a final renderer/process
check. Portside persists setup completion, starts its existing helpers and exits
its UI process without stopping Steam. Known launch failures retain the retry UI.
This supersedes earlier requirements for customer confirmation in this document.

The readiness report remains `visibleButUnverified` / `notVerified`; automatic
product completion does not synthesize manual graphical acceptance. Rendering,
interaction and game validation remain separate operator checks.

**Verified local checks:** `swift test --package-path apps/desktop` completed
164 tests, one optional signed-app probe skipped, zero failures. The new regression
checks automatic completion with detected Steam/window/webhelper and rejects
missing evidence or a renderer failure while preserving unverified diagnostics.
`swift build --package-path apps/desktop`, `./scripts/validate-production-policy.sh`
and `git diff --check` passed. No installed app/runtime was replaced, no graphical
session was relaunched, and no commit, push or publication was performed. Existing
local startup-privacy changes were preserved.


## Startup privacy follow-up — 2026-09-10 UTC

**Implemented but not end-to-end validated:** the owner reported microphone and
local-network permission prompts during Steam startup, without voice-chat use.
Read-only TCC inspection attributed microphone requests to Wine under the
Sikarugir launcher, whose installed signature lacked Hardened Runtime. New
packages harden the original launcher without audio-input permission, retaining
only the library-validation exception needed by the original signed SDK.
Packaging and native validation check the actual code flags and exact entitlement
set. The original SDK/engine signatures and bytes remain unchanged.

New wrappers configure Valve's `-preventsteamdiscovery` flag, observed next to
remote-client broadcast/listener code in the installed client. The desktop accepts
only this flag or the empty legacy configuration. This is targeted discovery
suppression, not a proof of no LAN access by all Steam/game features. See
[the policy and acceptance limits](SIKARUGIR_INSTALLATION.md#startup-privacy-restrictions--2026-09-10-utc).

**Verified local checks:** `python3.14 -B -m unittest discover -s scripts/tests`
passed 99 tests. The first run with system Python was rejected by the existing
Python 3.12+ safe-extraction requirement; no check was weakened. Desktop Swift
tests completed 163 tests, one optional signed-app probe skipped, zero failures;
runtime-host tests passed 24 tests. Both Swift builds, source audit, Wine and
winetricks snapshot validation, shell/JSON/plist syntax, production policy and
`git diff --check` passed. Local ad-hoc packaging from the exact verified pins
completed and its actual launcher restriction check passed. No installed runtime,
Steam session or macOS privacy decision was modified, and no publication occurred.

**Verified native runtime installation, scoped:** the separate
`python3.14 -B scripts/build-runtime/validate-sikarugir-installation.py`
run against the local working-tree archives passed new-prefix installation
(39.68 seconds), existing-prefix replacement (34.82 seconds), x64/x86 Windows
controls (exits 37/23), synthetic-data/metadata preservation, all component
signature checks and the new launcher restriction check. This ad-hoc build has
`distributionSignatureVerified=false` and `renderedInteractionVerified=false`.
The successful fixture was cleaned up by the validation script.

The optional native `--install-steam` probe exercised both Windows command
architectures and preserved its synthetic prefix through replacement. Its hardened
launcher ran winetricks and created the fixture Steam executable, but remained in
`SikarugirWineApp.waitUntilAllProcessesEnd()` with no launcher descendants. The
fixture server shutdown reported no running fixture server. Only that exact
fixture launcher was then stopped, causing the optional probe to fail. This is
not successful end-to-end Steam installation/termination evidence. The existing
user Steam session was preserved; the reason for the upstream wait remains
unknown, and the interrupted fixture diagnostics were retained locally.

Graphical startup without permission prompts, audio playback, and games with the
final Developer ID distribution remain unvalidated. Existing authenticated
runtimes keep their earlier behavior until a corrected runtime is installed.


## Automatic Steam opening follow-up — 2026-09-09 UTC

**Implemented but not end-to-end validated:** the existing-installation path now
opens Steam automatically after successful app/runtime/Steam checks, including
runtime replacement, unless a managed Steam session is already running. Fresh
setup already opens Steam automatically. The launch progress UI is shown while
opening; rendered interaction still requires explicit confirmation.

The live 0.1.41 installation reached ready at 23:13:54 UTC, followed by
`runtime host arguments are invalid` at 23:14:07 and
`steam_process_not_started` at 23:14:08. The installed plist selected the
Sikarugir launcher. Stale LaunchServices registration is the suspected routing
cause, not directly captured cache evidence. The desktop now forces registration
of the validated runtime URL before NSWorkspace opening, failing closed if that
registration fails. See [the launch correction](SIKARUGIR_INSTALLATION.md#automatic-opening-and-launchservices-refresh--2026-09-09).

**Verified local checks:** `swift test --package-path apps/desktop` completed
162 tests, one optional signed-app probe skipped, zero failures. The new fixture
checks legacy-to-Sikarugir replacement with cached Bundle metadata, forced
registration, argument separation, registration failure, and incomplete setup.
`swift test --package-path apps/runtime-host` passed 24 tests. Both corresponding
`swift build` commands, `./scripts/validate-production-policy.sh` and
`git diff --check` passed. These checks do not prove real LaunchServices cache
recovery or automatic rendered Steam startup in a customer installation.
No installed app/runtime was modified and no release was published; the fix
requires a corrected desktop distribution and graphical acceptance.

## Installation follow-up — 2026-09-05 UTC

**Verified, scoped:** the [reopen correction](INSTALLATION_REOPEN_FIX.md) passed
116 desktop tests (one optional probe skipped), the desktop build and production
policy. A disposable copy of the authentic signed/notarized app passed the new
Gatekeeper/quarantine preparation and opened at its exact requested path without
translocation. This follow-up does not establish complete customer bootstrap or
Steam acceptance; the audit matrix below retains its original scope.

## Local storage retention follow-up — 2026-09-06 UTC

**Implemented but not end-to-end validated:** desktop startup and successful
runtime installation now bound replaceable Portside storage to one rollback,
one failed wrapper and one legacy prefix recovery point, and remove abandoned
staging directories and direct download-cache entries after 24 hours. History
ordering accepts current millisecond names, legacy second names and filesystem
attribute dates when archive timestamps are invalid. Fixture tests verify entry
age, symlink exclusion, retention ordering and preservation of a synthetic
managed-prefix marker. The active Steam prefix and game libraries are never
cleanup targets.

**Verified manual cleanup, scoped:** with explicit user authorization, eight old
runtime rollback directories and re-creatable download caches were removed from
one real installation while retaining the newest `0.1.17` rollback. Portside
storage fell from approximately 39.6 GiB to 28 GiB and available disk space rose
from 181 GiB to 193 GiB. The active wrapper, managed prefix, Steam installation,
games and saves were excluded by exact path. This validates the manual target
selection, not startup execution of the revised maintenance code. Validation
passed 121 desktop tests with one explicitly unconfigured signed-app probe
skipped, the desktop build, production source policy and `git diff --check`.

## Steam first-launch follow-up — 2026-09-07 UTC

**Verified, scoped:** [the 0.1.28 investigation](STEAM_FIRST_LAUNCH_FIX.md) on
macOS 26.6.2 reproduced SIGKILL 9 using installed Wine 11.17/runtime 0.1.26 and
disposable direct/symlinked prefixes. `wine --version` succeeds, but the nested
arm64 loader fails. A minimal program with the same low-address 4 KiB layout
also receives SIGKILL, including with a valid Developer ID signature; its
standard arm64 and x86_64 controls execute. The cause is the recipe's arm64
Darwin loader layout, not an inference from AMFI messages or a prefix problem.
The corrected host, exercised with the installed engine in a disposable wrapper,
records `uncaughtSignal`, signal 9 and 97 ms, returning 137 to its caller.

**Implemented but not end-to-end validated:** source now selects x86_64
Wine/WoW64 via Rosetta, builds the pinned font dependency for that target, changes
engine identity to include architecture/recipe, and gates packaging/extraction
on real Windows command execution. Host receipts and desktop readiness separate
execution errors, signals, normal exits, absent Steam, missing window and absent
webhelper, and end early after termination with no managed children. New flags
are negotiated, so old hosts do not forward them to Steam. The everyday prefix,
installed runtime, native Steam, games, saves and credentials were preserved.

**Verified build and automated checks:** the source-built x86_64 engine archive
completed successfully (336,989,260 bytes, SHA-256
`d024d10dede017f62718773fe25bef358164fb57751c78f5ed6ab9fbf8877b2b`).
Both the install tree and an archive extracted outside the build tree executed
x64 `cmd` with expected exit 37 and x86 `cmd` with expected exit 23. The extracted
first-prefix probe took approximately 14 seconds. Wrapper and winetricks builds,
source audit, Wine/winetricks snapshot validation, JSON/shell/Python syntax,
production policy and diff whitespace checks passed. Final Swift test/build
results after review: 15 host tests passed; 132 desktop tests completed with one optional
signed-app probe skipped and no failures. Both Swift builds passed.

**Verified local bootstrap and official Steam installation after review:** a
fresh control reproduced Wine's modal optional Mono installer blocking before
WoW64 kernel32 files were complete. The production host now defers Mono/Gecko
registration only during prefix creation; no DLL override is persisted or used
for Steam/game launches. Desktop uses the official quiet winetricks Steam verb.
Two new fixtures completed host bootstrap in 15.126/17.760 seconds, both command
architectures in expected exits 37/23, and official Steam installation in
75.904/69.124 seconds with exit 0 and `steam.exe` present. The extracted-layout
gate now exercises the real host without test-only DLL overrides. Mono/.NET and
Gecko-dependent applications remain outside this bootstrap validation.
Final local `0.1.28-local` archives were rebuilt from the wrapper/winetricks source
and compiled-engine cache. `validate-clean-layout.sh` passed after extraction:
the engine checks succeeded, and actual host bootstrap completed in 16.686
seconds with both subsequent Windows commands returning expected exits 37/23.

**Implemented and locally tested production-blocker fixes:** release waits for
runtime assembly of its `target_sha`, checks source/build provenance and manifest
agreement, and fails closed on missing/failed/cancelled/expired matching evidence.
App-only changes reuse the recipe-selected engine in a fresh runtime assembly.
Thirteen release regression tests and actionlint pass; GitHub execution was not run.
Host capture now uses read events and termination notifications, ending at EOF
or two seconds after termination without SIGPIPE to descendants. UUID receipts
have seven-day/100-file historical retention with a five-minute reader grace;
fixture tests cover late writes, retention and preservation. Text-log rotation
remains a separate gap.

**Graphical Steam acceptance remains unvalidated:** during a 120-second probe
in the second fixture, managed Steam and steamwebhelper processes appeared after
normal loader exit 42. Scoped CoreGraphics returned no owned on-screen window;
screen-capture access was unavailable. No rendered login window or interaction
was verified. The fixture's processes were stopped and its temporary data removed.

**Unknown for final distribution:** no signed/notarized corrected runtime or
rendered interactive Steam acceptance is established. Of 35 installed Mach-O
files, all have ad hoc signatures; 34 Wine components verify, while the host's
resource seal fails strict verification. This separate packaging gap is not the
proved SIGKILL cause. The newly compiled x86_64 loader, ntdll and FreeType are
unsigned local outputs, not final distribution candidates. No security settings or installed artifacts were changed;
no publication, manifest update, commit, push or deploy occurred.

## Actions runner allocation follow-up — 2026-09-07 UTC

**Verified, scoped live inspection:** source revision
`a0d6e27d1f4b795f1452f561d6b5bb03e4abf992` was clean before these local changes.
Read-only GitHub API/log inspection found that
[release run 34124567328](https://github.com/andre-fig/portside/actions/runs/34124567328)
allocated its Linux runtime-wait job at 12:56:10 UTC; the polling step began at
12:56:21. It was awaiting the matching engine/runtime, not waiting for its own
runner to be assigned. [Engine run 34124509954](https://github.com/andre-fig/portside/actions/runs/34124509954)
allocated macOS at 12:55:53, installed tools for 84 seconds, restored cache for
12 seconds, then compiled Wine from 12:57:45 until cancellation at approximately
13:04:45. Logs show compiler work and an incompatible restored cache, not a
lint hang. Both runs were later observed cancelled; no cancellation was issued
by this task. The successful push-triggered runtime run had skipped assembly
and produced no qualifying runtime. No new production engine completed there.

**Implemented but not end-to-end validated:** release now reacts to CI/runtime
completion, checks both prerequisites for the same commit once on Linux and
exits when they are unfinished. There is no active cross-workflow polling job.
Global release concurrency and prior publication evidence suppress duplicate
automatic publication; missing/failed/cancelled/expired evidence cannot select
an older source. App-change scope and production destinations are preserved.
Native engine compilation/execution and runtime assembly/probes remain macOS;
engine/runtime publication and runtime Ed25519 manifest signing move to Linux
with transferred-archive source/run/hash/size checks. Temporary manifest keys
are removed at job completion. Detection and preflight share one Linux job per
build workflow. Engine push paths exclude assembly-only scripts; compatible
cache keys include observed toolchain/architecture and omit broad fallbacks.
Artifact uploads exclude temporary build trees and disable redundant compression
of archives; the runtime assembly handoff has one-day retention.

**Verified local automation/checks:** `core.hooksPath` was already `.githooks`;
no Git configuration change was needed. Pre-commit validates actual staged
shell/JSON/Python/workflow content. Pre-push selects both Swift test/build suites,
script regressions and existing backend/landing checks from changed paths.
Workflow lint requires actionlint. Linux CI retains independent production
policy/regression/backend gates; bypassable hooks are not a release trust root.

Commands/results for this follow-up:

- `python3 -B -m unittest discover -s scripts/tests -v`: 35 tests passed,
  including both event orders, duplicate suppression, native/Linux job proof,
  corrupt/missing/wrong-source artifacts and disposable hook fixtures.
- `swift test --package-path apps/runtime-host` and `swift build --package-path apps/runtime-host`:
  15 tests passed and build passed.
- `swift test --package-path apps/desktop` and `swift build --package-path apps/desktop`:
  132 tests completed, one optional signed-app probe skipped, no failures; build passed.
- Source audit, Wine/winetricks snapshot validation and production policy passed.
  Workflow lint, shell/JSON/Python syntax and `git diff --check` passed.
- The publication checksum validator read the existing 336,989,260-byte local
  engine archive successfully and rejected its use for another source/run.
  This is archive verification, not a new native engine build.

**Remaining validation:** the revised GitHub job graph, Linux signing/storage
handoff, cold/warm cache timing and remote publication require a subsequent
explicitly authorized push/run. No engine rebuild, production key usage, new
Steam graphical probe, workflow dispatch, commit, push, deploy or publication
was performed in this follow-up. The previous Developer ID/runtime notarization
and rendered interactive Steam acceptance gaps remain. Apple app notarization
still uses `notarytool --wait` within its macOS job.

The repository was public at inspection and uses standard hosted runner labels.
[GitHub billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
states those public-repository runner minutes are free; this does not establish
artifact/cache storage usage, account billing or larger-runner costs. The changes
reduce occupied runner time and retained temporary output; savings have not been
measured on the new workflows.

## Authorized Actions execution follow-up — 2026-09-07 UTC

**Verified, scoped:** the user subsequently authorized commit/push and monitoring.
Commit `aea61b82b11eaaf8bbd9d857f19a0d8edd2c0ea2` passed the real pre-commit and
pre-push hooks and was pushed to `main`. CI run `34127517737` passed. Engine run
`34127517724` passed Linux preflight and entered native compilation; the initial
runtime detection skipped assembly while the engine was being built, without
an allocated waiting job. App/desktop jobs were skipped by their existing
change filters because this commit changes automation only.

**Corrected during monitoring:** runtime completion triggered release run
`34127543832`, which failed promptly while resolving its source. The real GitHub
API reports the custom `Runtime production <sha>` title in both `name` and
`display_title`, instead of the fixed workflow name expected by the initial
fixtures. Routing now checks `.github/workflows/build-runtime.yml` or
`.github/workflows/ci.yml` through `workflow_run.path`; the source remains bound
to the explicit title and downloaded provenance. Regression fixtures use the
observed shape and reject an unrelated path. The subsequent 37 local script
tests, actionlint, policy and whitespace checks passed. Orchestration-only
changes no longer allocate a native runtime assembly, avoiding an extra build
while the already-authorized engine is compiling. Remote confirmation of this
follow-up and engine/runtime completion remains pending at this snapshot.

## Local Wine compilation correction — 2026-09-07 UTC

**Verified, scoped:** after approximately 30 minutes in the engine build stage,
user feedback explicitly required local compilation before push. Run
`34127517724` was cancelled by this task and confirmed completed/cancelled. Its
follow-up runtime run `34130805583` skipped native assembly; release routing
completed successfully. No engine or runtime was published by that cancelled
build. The previous optimization removed idle waiting but did not remove the
long hosted compile; it was insufficient for the user's cost/time requirement.

**Implemented but not end-to-end validated:** the revised pre-push exports the
outgoing committed source, builds/caches Wine locally and uploads unpublished
inputs to the existing bucket. GitHub engine automation contains no Wine compiler
invocation or compiler/cache setup. Linux checks exact source/recipe, size and
checksum; a ten-minute native job performs safe extraction and x64/x86 execution;
Linux publication requires its receipt bound to the archive and metadata bytes.
Missing input fails immediately instead of waiting or compiling remotely.
Ordinary app/docs/routing changes do not compile Wine locally.

**Local checks:** 46 Python script tests passed with Python 3.14, including missing
transfer configuration before compilation, local input without native CI proof,
wrong recipe/source, tampered proof/metadata, unsafe archive extraction and local
hook routing. AWS CLI was installed locally for the input handoff. Existing local
Wine cache and the previously compiled x86_64 engine remain preserved. No everyday
prefix, installed runtime, game, save or credential was changed. Gatekeeper and
quarantine checks remain intact; the local AWS CLI installation added its Homebrew
dependencies and upgraded OpenSSL as required by that package.

**Additional local-build finding:** the existing install tree contains personal
build paths in native loader/ntdll installation constants and PE debug data. The
recipe now uses a virtual Wine prefix with DESTDIR installation and native/PE
compiler prefix maps. A new audit rejects personal paths without echoing values,
before packaging and after CI extraction. Forty-nine Python tests passed with
Python 3.14 after this addition. The previous cached recipe/macOS/Clang matched,
but the observed Xcode version changed, so the local build correctly rejected
that compilation cache. These recipe changes require a new locally validated
engine; the previous archive must not be uploaded as the corrected output.
The first exact-commit local build completed in approximately 14 minutes and
returned expected version/x64/x86 statuses 0/37/23; this preceded the path-clean
recipe and is not a publishable candidate. Local compiler logs now redact source,
checkout and home paths, with a regression proving failure still blocks push.
Actionlint, source audit, shell syntax, production policy, documentation file
links and diff whitespace checks passed. Invoking the actual pre-push hook with
the outgoing refs ran 49 tests (the system Python skipped the safe-extraction
test; Python 3.14 ran all 49) and policy, then failed on missing local storage
configuration before compilation or upload. No hook was bypassed.

**Verified corrected local engine:** the exact-commit build at `ba445037` finished
in 1,488.7 seconds with status 0. Version/x64/x86 controls returned 0/37/23 and
the complete personal-path audit passed. A newly built host/winetricks fixture
created its disposable symlinked prefix in 23.238 seconds (status 0), executed
x64/x86 commands with expected statuses 37/23, and installed official Steam in
71.408 seconds (status 0). No Steam authentication or graphical acceptance was attempted.
The local invocation of the CI consumer safely extracted the final archive,
passed its path audit and returned 0/37/23 (x64: 13.391 seconds). The publication
validator accepted its matching local-review receipt and checksums; this is a
local consumer test, not proof of a hosted run or storage publication.

**Verified provider discovery:** local storage environment/profile files were
absent, but the existing authenticated Railway CLI has the linked Portside
production API's five storage variables. The optional local provider reads those
values only into memory after matching repository and environment; no variable
write, deployment or secret export occurred. Fifty-two Python 3.14 tests passed,
including wrong-project/environment rejection and prevention of mixed providers.
Actual input upload, revised hosted consumer/publication and final signed/graphical
acceptance remain pending at this snapshot; hosted Wine compilation will not restart.

**Additional distribution blocker found before upload:** the first path-clean
engine inherited macOS 26.0 as its minimum OS from the local SDK; Wine, its nested
loader/ntdll and FreeType all reported that floor through `vtool`. This conflicts
with the app/wrapper's macOS 13+ contract and the macOS 15 native consumer. The
Wine/FreeType recipes now explicitly target 13.0, the compilation cache includes
that target, and every engine Mach-O must pass architecture/deployment checks.
Fifty-five Python 3.14 tests passed. The earlier local archive is not eligible
for upload; this source correction requires a new local build.

**Verified final local build and hosted engine pipeline:** source `02bad9d1`
completed its macOS 13-targeted build in 1,138.1 seconds. All 34 Mach-O files
passed x86_64/deployment checks and the personal-path audit passed. Actual host
bootstrap returned 0 in 23.045 seconds; both Windows command architectures
returned 37/23; official Steam installation returned 0 in 69.415 seconds. A
separately extracted consumer fixture passed the same platform/path checks,
returned 0/37/23 and passed publication evidence validation. No graphical window
or Steam authentication was part of these checks.

The normal pre-push ran its checks, reused the completed exact-commit input,
uploaded it through the linked production Railway provider and pushed
`9b0a70e6..02bad9d1`. Secrets remained in memory; no Railway variables or services
were changed. [Engine run 34141434553](https://github.com/andre-fig/portside/actions/runs/34141434553)
then passed: Linux source/input validation took 22 seconds, the complete macOS
job took 2 minutes 5 seconds and Linux publication took 27 seconds. Hosted checks
confirmed all 34 Mach-O files and expected 0/37/23 exits (x64: 33.826 seconds).
There was no hosted Wine compiler/toolchain/cache step. The published archive
is 337,106,284 bytes, SHA-256
`30fad3f925bdb550cb584833bd43cd70978c628d1bf7ec85e33ff04379ed159b`, engine
`wine-Wineversion11.17-36b6a2cf679f-x86_64-fe553e2d62ce`.

CI passed; the initial runtime, desktop and release detection paths skipped
their unneeded native/application jobs. Engine completion automatically started
[runtime run 34141696153](https://github.com/andre-fig/portside/actions/runs/34141696153)
for that same source. That runtime completed and published signed manifest
`0.1.33`: native assembly/validation took 11 minutes 5 seconds and Linux signing/
publication took 55 seconds. Hosted real-host bootstrap returned 0 in 46.554
seconds with subsequent 37/23 exits. No application release/backend promotion
or graphical/Developer ID distribution acceptance follows from those results.

**Runtime packaging follow-up:** the successful runtime log attributes 8 minutes
35 seconds between wrapper completion and engine reuse to engine fetch/validation/
repackaging on macOS. Source now performs that work on Linux, with BSD metadata
normalization and parallel XZ for archive writes. A receipt binds source, workflow,
runtime version, engine metadata and archive bytes before native use. macOS keeps
host compilation and native checks; its storage credentials/client setup and
engine repackaging are removed. Missing prepared evidence fails without fallback.
Sixty-one Python 3.14 tests, actionlint, shell/source audits, policy, documentation
links and diff checks passed. The actual published `0.1.33` runtime was downloaded
into a new build fixture: prepared receipt record/verification and native fetch
passed with no storage credentials, then all 34 Mach-O files and 0/37/23 engine
controls passed. Real host bootstrap completed in 14.567 seconds with subsequent
37/23 exits and clean layout validation passed. A small disposable parallel-XZ
archive preserved its extracted contents. Hosted Linux preparation/native handoff
remains pending at this snapshot.

**Verified hosted Linux preparation and native consumption:**
[runtime run 34144111927](https://github.com/andre-fig/portside/actions/runs/34144111927)
for source `56fc8b66` published runtime `0.1.34` successfully. Linux preparation
took 4 minutes 23 seconds; macOS host build/validation took 3 minutes 24 seconds
(previously 11 minutes 5 seconds); Linux manifest signing/publication took
35 seconds. The macOS job was allocated only after the prepared artifact was
available. Its receipt verification passed, all 34 Mach-O files passed platform
checks, engine commands returned 0/37/23, and actual host prefix bootstrap
returned 0 in 63.015 seconds with subsequent 37/23 exits. Clean layout passed.
CI and completion routing passed; desktop/application publication jobs were
skipped under the former desktop-only release filter for these runtime changes.
That filter left the validated runtime undiscoverable; see the correction below.
No Wine build was triggered by this follow-up. Application/backend promotion and rendered Steam
acceptance remain separate, unperformed steps; no everyday prefix or installed
runtime was modified during these checks.

## Automatic runtime release follow-up — 2026-09-07 UTC

**Verified automatic publication and discovery, scoped:** user-authorized automatic
runtime publication now uses successful same-source runtime assembly/publication
and CI as its gate. The duplicate last-commit desktop/packaging filter is removed.
Wine/wrapper/winetricks/packaging changes and multi-commit pushes ending in docs
can reach app publication and backend registration. Docs-only or skipped-runtime
runs still cannot allocate a native app release. Completion checks remain one-shot
Linux jobs; duplicate publication suppression and source/run/artifact validation
remain intact. Failed engine completions are rejected before runtime allocation.
Registration now checks out the validated source instead of a later main revision.

The observed gap was [release run 34144747392](https://github.com/andre-fig/portside/actions/runs/34144747392):
its log said `No app or packaging files changed; skipping production release`
after runtime `0.1.34` passed and uploaded. Neither app publication nor backend
registration ran. This follow-up changes that automatic trigger explicitly; it
does not treat a storage upload as customer availability or graphical acceptance.

**Verified local checks:** 65 Python 3.14 script tests passed, including execution
of the workflow gate against strict fake Actions evidence. Actionlint, shell
syntax, runtime source audit, Wine/winetricks snapshot checks, lock/dependency
JSON, production policy, documentation links and `git diff --check` passed.
Swift/application code did not change; the earlier Swift test/build results
remain scoped to the first-launch correction. The normal pre-push repeated 65
tests with one Python 3.9 safe-extraction skip (the full Python 3.14 run passed
all 65), lint and policy, then pushed `8b9c0a88` successfully. A read-only gate
control against the original `56fc8b66` source selected CI `34144111993` and
runtime `34144111927` with `ready=true`; it made no external writes.

**Verified initial completion routing:** CI passed for `8b9c0a88`. Its automatic
[release check 34146349458](https://github.com/andre-fig/portside/actions/runs/34146349458)
finished in 12 seconds with `runtime_not_ready` and no native app allocation,
while runtime preparation continued on Linux.

**Verified runtime-to-release handoff:** [runtime run 34146313432](https://github.com/andre-fig/portside/actions/runs/34146313432)
published `0.1.35`; Linux preparation took 4 minutes 40 seconds, native assembly
4 minutes 13 seconds and Linux signing/publication 41 seconds. Prepared evidence
matched source/run/version/bytes. Wine controls returned 0/37/23, real host prefix
bootstrap returned 0 in 65.506 seconds, subsequent Windows commands returned
37/23 and clean layout passed. No Wine compiler ran. Completion automatically
started [release run 34147014277](https://github.com/andre-fig/portside/actions/runs/34147014277);
its 17-second Linux gate accepted matching CI/runtime and allocated the native
app job. No manual workflow dispatch was used.
Before registration, read-only public discovery still returned runtime `0.1.26`
and app `0.1.28`, confirming that upload alone had not updated customers.

**Verified app publication and public discovery:** release `34147014277` completed
successfully. Its macOS job took 7 minutes 47 seconds, including 5 minutes 4 seconds
restoring the existing 2.6 GB Swift cache, 53 seconds compiling the app and 57
seconds notarizing/stapling. Both Apple submissions returned `Accepted`, strict
bundle verification and Gatekeeper assessment passed, and app `0.1.35` uploaded.
Linux registration took 14 seconds and checked out `8b9c0a88`. A subsequent public
API check returned runtime `0.1.35` bound to that commit with components matching
the retained signed manifest, and the appcast announced app `0.1.35`. These results
verify the entire automatic runtime-to-app publication/registration path, including
a runtime change without a desktop change. Swift cache restoration remains a
measured native-job cost; no Wine compilation or cross-workflow polling occurred.

**Remaining acceptance limits:** the app's Developer ID/notarization result does
not establish Developer ID signing of the separately downloaded Wine/runtime
Mach-O files. Rendered interactive Steam acceptance and customer installation of
this release remain unvalidated. No everyday prefix or installed runtime was used
as a validation fixture.

## Live 0.1.35 installation follow-up — 2026-09-07 UTC

**Verified installation and process readiness, scoped:** read-only observation of
the user-initiated installation confirmed app `0.1.35` in `/Applications` and
runtime wrapper/manifest `0.1.35`, bound to source `8b9c0a88`. App update/relaunch
was verified at 18:36:06 UTC; runtime installation completed at 18:37:12. The
wrapper's prefix link still points to the existing external managed prefix.
The runtime host started Wine at 18:37:14; at 18:39:02 the desktop recorded
`ready` and detected a managed window with webhelper. At 18:40:52, one Steam
process, eight webhelpers and its runtime host remained alive. The launch
receipt remained `running`; the former immediate SIGKILL 9 was not reproduced.
No agent-initiated prefix changes, launches, termination or cleanup were used.

**Verified remaining upgrade defect:** the live `wineboot` displayed the Wine
Mono installer, corroborated by the user's screenshot and its accessibility
window title. `PortsideRuntimeInstaller` runs the controlled `--create-prefix`
bootstrap only for a nonexistent prefix; the existing-prefix branch only links
it. The host's transient optional-addon deferral applies only to that bootstrap
command. A subsequent Wine update during ordinary Steam launch can therefore
show the modal addon installer on an existing prefix. New-prefix tests did not
cover this path. The user confirmed choosing Cancel in the Mono dialog; Steam
then reached process/window readiness.

**Blocked graphical acceptance, user-confirmed:** the user reported that the
Steam window was entirely black. Current-session `cef_log.txt` records ANGLE's
D3D11/EGL context failure: requested GLES 3.0 exceeded the reported maximum 2.0.
Fallback attempts required Vulkan 1.1 and returned an incompatible-driver error;
the GPU subprocess repeatedly exited during initialization. `webhelper_gpu.txt`
records that its GPU process could not boot after repeated SwiftShader failures.
These are concrete renderer failures consistent with the observed black window;
the underlying graphics compatibility fix has not been established by a
controlled comparison. `ready`/`visibleButUnverified` must not be reported as a
usable Steam interface. The current Wine command probes test execution only.

Steam's own updater downloaded approximately 212 MB, and the host subsequently
recorded a normal exit with status 0, reason `exit`, after 271.954 seconds. At the
next observation, no Wine/Steam/webhelper process remained. No agent action
closed or restarted them, and the evidence does not establish whether the user
or the updater initiated shutdown. No Steam flags, graphics settings, prefix
contents or trust settings were changed as part of this observation.

The user also observed macOS's Intel compatibility deprecation notification.
The shipped Wine engine is x86_64 and uses Rosetta on Apple silicon. Apple's
[Rosetta support guidance](https://support.apple.com/en-ca/102527) states general
availability through macOS 27, with restricted legacy-game functionality from
macOS 28; this notification is a future compatibility limit, not the observed
Mono bootstrap blocker. Screen capture was not authorized, so process/window
metadata is not claimed as visual acceptance. No account or credential files
were inspected.

## Steam graphics correction follow-up — 2026-09-07 UTC

**Verified renderer cause and controls, scoped:** the
[0.1.35 graphics investigation](STEAM_GRAPHICS_FIX.md) used only disposable
homes/prefixes and the metadata-checked local x86_64 engine archive with SHA-256
`30fad3f925bdb550cb584833bd43cd70978c628d1bf7ec85e33ff04379ed159b`.
On the Apple M4 Pro/macOS 26.6.2, WineD3D advertised OpenGL 4.1 but only D3D11
feature level 9_3. Valve ANGLE created GLES 2 but rejected GLES 3. Its SwiftShader
fallback loaded Wine's builtin Vulkan loader, which reports no compiled Vulkan
support, and reproduced Vulkan -9 and GPU initialization failures. Selecting
Valve's native Vulkan loader allowed its bundled SwiftShader to create GLES 3
and render the expected RGBA pixel `64,128,191,255`. Vulkan -9 is not SIGKILL 9.
The updated Steam client (`1788652215`, CEF 126, ANGLE `5d4df51d1d7d`) selected
`egl-angle/swiftshader`, Vulkan 1.3.0, in the controlled candidate. Identical
Steam/ANGLE/loader/SwiftShader hashes separated the loader policy from Steam's
own update. Initial D3D11 errors can remain before successful fallback.

**Implemented but not end-to-end validated:** from local base `0e5a5eb2`, the
installer now prepares existing and new prefixes once per runtime installation
or repair. The host runs `wineboot -u -r` with transient Mono/Gecko deferral and
then sets `vulkan-1=native,builtin` only in Wine's `steamwebhelper.exe` AppDefaults.
No DLL override is inherited by games. The `-r` avoids Run/Startup programs:
the baseline fixture executed a synthetic startup command during upgrade,
whereas the final host did not. Final bootstrap took 15.601 seconds; existing
prefix update took 7.520 seconds, preserved a synthetic marker, and x64/x86
controls returned 37/23. Steam software UI rendering can increase CPU/power use;
game WineD3D and absent native GPU Vulkan support are unchanged.

The desktop now retains an interface-verification screen after
`visibleButUnverified`. Only explicit user confirmation marks graphical readiness
and closes the launcher. A blank-window report, Steam closing or an explicit
current exhausted GPU initialization report fails the attempt. Bounded GPU log
reads snapshot prelaunch bytes, filter old timestamps and allow newer starts or
initialized ANGLE reports to clear prior failures. Transient EGL errors alone
do not fail a launch or prove successful rendering.

**Verified automated checks:** 16 runtime-host tests and host build passed;
139 desktop tests completed with one optional signed-app probe skipped and no
failures, and the desktop build passed. The desktop suite initially encountered
an EPERM reading a protected Sparkle test receipt; an isolated rerun and the
final complete suite passed without changing file protection. All 65 script
tests, source audit, Wine/winetricks snapshot checks, production policy,
workflow lint and diff whitespace checks passed. The detailed report lists
commands and the before/after real-host controls.

**Blocked rendered interactive Steam acceptance, user-confirmed:** screen capture
was unavailable; no screenshot was captured or inspected in that investigation.
The user subsequently confirmed that the open candidate Steam window remains
entirely black. The loader change fixes the measured initialization failure but
has not fixed the visible Steam interface. Healthy CEF renderer reports and
offscreen pixel controls are insufficient; composition/presentation remains under
investigation.
No login or game interaction has been accepted. Rosetta remains required, and
the Intel notice was not suppressed. No installed runtime/prefix or native Steam
was changed. No new Wine compilation, signature exception, sandbox-disabling
flag, workflow change, commit, push, dispatch, deploy or publication occurred.
A newly authenticated runtime/signed app release and installed graphical
acceptance remain necessary before claiming a customer fix.

## Sikarugir integration direction correction — 2026-09-08

**Verified architectural gap:** the project owner clarified that Portside must
automate Sikarugir installation/configuration/launch. The current wrapper builds
an independent Swift host and directly invokes Wine. Using the Sikarugir Wine
fork is not the requested launcher/SDK/runtime integration. D15 supersedes that
architectural substitution without relaxing source-build or trust constraints.

**Verified reference inventory, not graphical acceptance:** inspected the
official Template 1.0.15 archive, 87,477,092 bytes, SHA-256
`34273bcce885ce5a7fd6937af9ea344bb9961de7d55d6193f7413142e835c8c3`.
Its actual members include Sikarugir Launcher/SDK, DXMT x86/x64 DLLs and Metal
bridge, D9VK, MoltenVK, KosmicKrisp and GStreamer. The plist advertises macOS 14.
These are omitted from or differ from the Portside assembly. The archive was
read in a disposable directory without extraction, installation or execution.
The inspection pin is separate from production source locks/build inputs.

**Implemented diagnostic/documentation correction:** added an inspector and
synthetic regressions, corrected root/host/build instructions, and documented
the source/build/adapter migration in [SIKARUGIR_INTEGRATION](SIKARUGIR_INTEGRATION.md).
The app/runtime implementation remains the previous local candidate. No claim
is made that this change migrates the runtime or fixes the visible black window.

**Verified checks:** `python3.14 -B -m unittest discover -s scripts/tests -v`
passed all 70 tests, including five new reference-inspection tests. The actual
pinned template passed the inspector. Source presence, Wine/winetricks snapshot
audits, `validate-production-policy.sh`, `actionlint .github/workflows/*.yml`,
changed-document local links, Python/JSON syntax and `git diff --check` passed.
Prior host/desktop tests and
build results remain scoped to the preceding candidate; no Swift implementation
was changed in this direction-correction step.

**Blocked runtime migration:** current public Wrapper/Engines/FOSS trees do not
provide the launcher/SDK sources and matching complete build recipe. Access was
requested from the project owner. There was no upstream-author message or
precompiled commercial fallback. Installing renderers into the independent
host would not by itself satisfy the clarified integration requirement.

**Graphical result:** the earlier candidate remains user-confirmed black.
The later fixture-only software-composition-start control changed log behavior
but has no visual/interaction acceptance. No screenshot or Sikarugir graphical
success is claimed. Installed runtime, everyday prefix and native Steam remain
untouched. No Wine rebuild, security exception, commit, push, workflow change,
dispatch, deployment or publication occurred in this step. A future migration
needs new source builds, signing/authenticated release and real GUI acceptance.

## Historical Sikarugir test after checkpoint commit — 2026-09-08

**Verified checkpoint and historical source test:** user-authorized commit
`a4a0b952` preserves the preceding investigation and original live 0.1.35 report;
no push occurred. A separate detached worktree at `8e9eda9e` passed all 25
historical desktop tests and its build. Checksum-verified Template 1.0.11,
WS12WineSikarugir10.0_6 and historical winetricks were tested with the unchanged
historical installer classes in a new disposable home/prefix.

**Verified runtime progress:** prefix creation and Steam installation returned 0.
Two fixture Mono prompts required cancellation. The external prefix retained its
synthetic marker. The first Steam opening reached a fatal-error window during
the Win32 update; its precise condition was not read. A scoped restart preserved
downloads and advanced to Win64 Steam `1788652215`, matching the client used in
the previous 0.1.35 control. No everyday data/runtime was accessed or changed.

**Not an acceptable graphical fix:** the historical engine injects the webhelper
switches `--no-sandbox --in-process-gpu --disable-gpu`. The observed launch matches
the app-specific workaround strings in both original `kernelbase.dll` members,
whose bytes still match the official downloaded archive. Portside's historical
Steam arguments were empty. The test was stopped upon identifying this behavior;
only fixture-owned launchers and its explicitly scoped wineserver were stopped.
No rendered/interactive Steam acceptance or screenshot is claimed. Screen capture
remains unavailable. The history is not evidence that the unchanged old engine
satisfies the retained sandbox constraint.

Strict whole-wrapper signing also conflicts with the historical mutable/external
prefix layout; a separate disposable signing control documented that boundary.
See [SIKARUGIR_LEGACY_VALIDATION](SIKARUGIR_LEGACY_VALIDATION.md) for exact artifact
hashes, source/test scope, updater stages, signature limits and inconclusive
diagnostic probes. These new results remain uncommitted after the authorized
checkpoint; there was no additional commit, push, release or publication.

## Sikarugir renderer-overlay continuation — 2026-09-08

**Verified, graphical failure persists:** a disposable original Sikarugir
Template 1.0.11 with Portside's Wine 11.17 ran x64/x86 controls and installed
Valve Steam. Identical CreateProcess controls reject the old engine's injected
sandbox/isolation switches (42) and preserve arguments through the new engine
(0). Steam updated to Win64 `1788652215` without the historical manual restart.
Owned-window screenshots were captured and inspected; they are black. The user
also confirmed the final software/native-Vulkan fixture remained black.

**Implemented and locally validated:** a checksum-pinned source patch supplies
Sikarugir's missing `WINEDLLPATH_PREPEND` contract. A full local Wine rebuild
completed; patch bytes bind engine/cache identity and accompany engine/runtime
provenance and the SPDX inventory. The known sandbox-disabling kernelbase
workaround is rejected before engine execution. No precompiled Sikarugir input
was added to commercial builds. Existing-prefix preparation with real Wine
preserved synthetic data and skipped startup entries.

**Verified remaining rendering defects:** without the patch, `DXMT=1` still
loads WineD3D. With it, the reference DXMT loads but needs its absent bridge PE
DLL provisioned. Supplying that original dependency only in the fixture allows
D3D11 FL 11_1 device creation. Actual Steam then reaches an explicit unsupported
cross-process swapchain path (`E_FAIL` / CEF `EGL_BAD_ALLOC`). That restriction
also exists in the newer inspected DXMT source. A software control with native
Valve Vulkan initializes GLES 3 but remains black. Its final presentation cause
is Unknown; removing log messages is not an accepted fix.

**Implemented diagnostic correction:** current explicit CEF window-surface
failures now have a separate failure code. Bounded per-session readers reject
historical/partial/out-of-prefix records, account for rotation and yearless CEF
timestamps, and compare recovery times across logs. A later device-capability
report cannot clear a presentation failure. Window/helper detection still cannot
authorize ready without rendered content and interaction confirmed by the user.

**Verified checks:** 16 host tests/build; 145 desktop tests (one optional skip,
no failures)/build; 80 script tests; full local Wine build and extracted
engine Windows/native/privacy checks; real new/existing-prefix preservation
fixtures; source/snapshot audits, policy, shell/JSON checks and workflow lint.
The [detailed continuation](SIKARUGIR_OVERLAY_VALIDATION.md) records hashes,
before/after controls, timings, commands and limitations. Original live and
historical reports remain intact.

**Blocked:** complete source-built Launcher/SDK integration still needs matching
sources and a build/configuration recipe absent from the inspected public trees.
Graphical presentation still needs an isolation-preserving fix and actual
rendered interaction, followed by signed matching app/runtime release validation.
The fixture is stopped; installed runtimes, everyday prefixes and native Steam
are preserved. Rosetta dependence and the Intel deprecation notice remain.
No further commit, push, dispatch or publication occurred.

## Original Sikarugir baseline authorized retest — 2026-09-08

**Verified: rendered Steam login and real interaction.** After the project owner
withdrew the restrictions previously cited against the original engine, the
historical disposable Template 1.0.11 / WS12WineSikarugir10.0_6 test was resumed.
Original engine DLL hashes and launcher/SDK component signatures passed. Steam
remained at the same updated client `1788652215`, with an unchanged executable
hash during this retest.

Owned-window screenshots were captured and visually inspected: the login content
was rendered. Targeted keyboard navigation and Space changed **Remember me** from
checked to unchecked in the subsequent image. No account credentials or login
were supplied. The engine's original injected switches were observed unchanged;
the result does not isolate which switch or engine patch is necessary.

The [retest report](SIKARUGIR_RESTORE_VALIDATION.md) supersedes the earlier lack
of historical graphical acceptance. The fixture was stopped using only its
verified launcher and prefix-scoped wineserver; its synthetic marker remained
unchanged and no fixture Steam/helper executable holders remained. Everyday data
and installed runtimes were preserved. Main's current runtime implementation has
not yet been migrated to this working reference. Full bundle signing, restored
product packaging, authenticated release and account/game acceptance remain
separate work. No new commit, push, dispatch or publication occurred.

## Sikarugir replacement started — 2026-09-08 UTC

**Verified checkpoint:** the owner-requested commit `cb02472b` preserves the
previous investigation, renderer corrections, original-runtime interaction
evidence and all existing status records. The commit hook passed; no push,
dispatch, deployment or publication occurred. The replacement below is subsequent
uncommitted work. D19 records the approved original component input contract.

**Implemented but not end-to-end validated:** a local candidate builder verifies
the pinned Template 1.0.11, WS12WineSikarugir10.0_6 and original winetricks by exact
size/hash, checks original launcher/SDK component signatures, preserves their
bytes/notices and adds the source-built maintenance helper. Provenance identifies
Sikarugir as the binary producer and Portside as assembler, with
`distributionReady: false`. The original Sikarugir launcher remains the native
application entry point. Desktop validates it separately from the helper, never
forwards Portside UUID arguments to it, and retains existing legacy runtime
support. The helper routes component setup through `WSS-winetricks` and limits
optional-addon deferral to explicit prefix preparation. It rejects normal Steam
launches in this integration mode.

**Verified native controls:** real first-prefix preparation returned only after
all three registry files existed (18.803 seconds). Existing-prefix preparation
completed in 4.686 seconds, preserving a synthetic marker and skipping a
synthetic startup entry. Windows x64/x86 commands returned expected 37/23.
Official Steam installation through the original launcher completed in 66.937
seconds with status 0. The actual desktop core validated and opened the final
candidate; its helper also prepared an existing prefix in 13.892 seconds. A
delayed registry-flush defect found in the first candidate was fixed and covered
by a regression test. These controls used disposable prefixes and private homes.

**Graphical acceptance: Unknown.** Steam updated from its Win32 bootstrap to
Win64 client 1788652215. An updater window appeared, but capture raced its
replacement. No final visible login window or interaction was established in
the candidate. This also occurred when using the previously working synthetic
prefix and when subsequently replaying the original wrapper. The comparison
therefore does not prove an entry-point, prefix or updater cause. No new usable
graphical screenshot was obtained. The earlier original-runtime rendered login
and checkbox interaction remain valid, separately scoped observations; they do
not establish acceptance of the new candidate. Both synthetic markers were
preserved, the candidate link was restored, and only fixture-owned processes
were stopped. No everyday prefix or installed runtime was modified.

**Verified checks:** `swift test` and `swift build` for both runtime-host and
desktop passed (23 host tests; 152 desktop tests with one optional signed-app
network probe skipped). `python3.14 -B -m unittest discover -s scripts/tests -v`
passed 87 tests. Production policy, source audit, Wine/winetricks snapshot
validation, JSON/shell syntax, actionlint and `git diff --check` passed. Candidate
assembly succeeded against the actual pinned archives. No Wine compilation or
external publication was needed for these checks.

**Remaining product integration:** the local candidate is not yet selected by
the production installer or commercial assembly. Engine transfer/layout,
installer migration fixtures, final provenance/SBOM, full bundle signing and
authenticated app/runtime artifacts from the same commit still require work.
Component signatures do not prove full-wrapper signing or notarization. Rosetta
and the original engine's previously documented Steam compatibility behavior
remain dependencies. Final rendered interaction, account login and game behavior
are not established. See [the adapter report](SIKARUGIR_ADAPTER.md) for the exact
contract, controls and limitations.

## Executive assessment

The repository implements the native application/install/update pipeline, a
Portside source-build runtime, commercial license protocol and API artifact
control plane. A clean customer journey is not established by this audit.
Checkout fulfillment is incomplete, runtime recovery/trust gaps remain, and
external deployment/signing/payment state was not queried.

The current system uses **production only**, **one artifact bucket**, and
**automatic qualifying releases after CI**. Staging-before-production and a
universally manual promotion pipeline are not the current implementation.
Future agents still require explicit task authorization for external publication.

## Operational evidence matrix

Definitions are in [TESTING](TESTING.md). “Not verified during this audit”
qualifies external/historical evidence; it is not a sixth operational state.

| Area                                              | Status                                   | Evidence                                                                                       | Missing validation                                                                     | Next action                                                                   |
| ------------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Source policy and snapshot identity               | Verified                                 | Production policy passes; six source snapshot digests match lock; source-presence audit passes | Does not prove compiler output, legal approval or reproducibility                      | Repeat when snapshots change                                                  |
| Shell/JSON/plist/workflow syntax                  | Verified                                 | 35 shell/hook files, 18 JSON/resolution files, five plists/entitlements; actionlint passes     | Script execution/remote job results                                                    | Run affected area tests for code changes                                      |
| Committed runtime manifests                       | Verified                                 | Both blocked empty fixtures fail production structural validator as expected                   | No authentic usable runtime manifest inspected                                         | Use approved signed release evidence for integration testing                  |
| App installation and bootstrap                    | Implemented but not end-to-end validated | Installer, bootstrap, preflight and test sources; historical partial report below              | Full commercial first launch, authorization denial, update/Steam sequence              | Dedicated account + signed candidate acceptance                               |
| Sparkle                                           | Implemented but not end-to-end validated | Coordinator, tests, appcast generation and release scripts                                     | Normal/critical install, relaunch and expected-version checks with two actual builds   | Authorize isolated fixture feed/builds; do not invent a staging service       |
| Developer ID / Hardened Runtime                   | Unknown                                  | Signing script; prior local candidate report                                                   | Current identities, final artifacts and verification                                   | Validate final signed artifacts in authorized environment                     |
| Notarization / staple / DMG                       | Unknown                                  | Notarization/DMG scripts; prior candidate report                                               | Current Apple result and final app/DMG tickets                                         | Verify exact final artifacts; ZIP contains stapled app                        |
| Wine engine build                                 | Implemented but not end-to-end validated | Recipe, lock, source digests, engine resolver                                                  | No fresh compiler run or Wine execution                                                | Build with recorded tools and preserve evidence                               |
| Runtime assembly                                  | Implemented but not end-to-end validated | Wrapper/host/winetricks assembly and persistent-engine fetch                                   | Current stored engine + complete artifact layout/build result                          | Fetch matching approved engine and assemble in authorized build area          |
| Runtime signed manifest delivery                  | Implemented but not end-to-end validated | Signer, backend publish verifier, client verifier, stable API redirect                         | Real signed discovery/download/checksum/install                                        | Trace one release across storage, DB and desktop                              |
| GitHub Actions execution / environment reviewers  | Unknown                                  | YAML and static lint only                                                                      | Current runs, secrets, approvals, branch protection                                    | Inspect externally only in an authorized operational task                     |
| Artifact publication / storage policy             | Unknown                                  | Single-bucket publishers and S3 client                                                         | Object existence/hash, public/private policy, retention and backups                    | Validate the configured bucket and final URLs                                 |
| Railway API/worker/PostgreSQL/landing             | Unknown                                  | Dockerfile, service JSON, worker and Railway connector                                         | Deployed revision, readiness, migrations, connector configuration                      | Verify provider configuration and exact running revision                      |
| Cron synchronization                              | Planned                                  | Cron entrypoint currently logs startup only                                                    | Actual periodic work                                                                   | Implement an explicit job if required                                         |
| Stripe payment / Apple Pay / DNS / email services | Unknown                                  | Checkout call and proposed configuration names                                                 | Live/test-mode payment/domain/provider evidence                                        | Use a separately authorized commerce validation                               |
| Checkout fulfillment                              | Blocked                                  | `getOrderStatus` always pending; no webhook/purchase writer/license issuer/email handler       | Complete paid purchase → delivered license                                             | Implement fulfillment with authenticated, idempotent payment processing       |
| Existing-license activation/refresh/offline use   | Implemented but not end-to-end validated | P-256 device proof, Ed25519 token, Keychain, backend tests                                     | Real DB concurrency, transfer/revocation and device flow                               | Dedicated license fixtures and integration tests                              |
| Clean runtime installation                        | Blocked                                  | Source-inferred nested prefix link in operator script; host/desktop fixtures exist             | Fix harness prefix identity, then authentic artifacts + test account + Valve/Apple/GUI | Follow [VALIDATION](VALIDATION.md) without cleaning user data                 |
| Steam rendered login / interaction / continuity   | Unknown                                  | Readiness code deliberately cannot prove visual success                                        | Real rendered interactive window and updater/close behavior                            | Human confirmation on a real Mac                                              |
| Game execution                                    | Unknown                                  | Compatibility source and Unturned fixture                                                      | Download, launch and usable rendered game scene                                        | Control-game acceptance; no universal compatibility claim                     |
| App/runtime rollback                              | Blocked                                  | Signed rules and recovery code exist, but target/selection defects below                       | Reliable previous-version recovery and data preservation                               | Resolve contract defects, then inject failures with disposable data           |
| Prefix, games and credential preservation         | Implemented but not end-to-end validated | External managed prefix/symlink design and fixtures                                            | Interrupted setup/update/repair/rollback with real layout                              | Validate synthetic markers and persistence without touching everyday accounts |
| Sentry delivery / privacy operations              | Unknown                                  | Sanitizer and SDK setup code; logging gaps below                                               | Live delivery, retention/deletion process and complete export audit                    | Review all producers and authorized service settings                          |
| English product language                          | Implemented but not end-to-end validated | Native metadata/new bootstrap strings; release metadata check                                  | Existing landing copy is Portuguese                                                    | Separate copy change; no production copy edited in this audit                 |

## Concrete risks and next milestones

1. **Runtime integrity and recovery:** pending local archives are not authenticated
   again at apply time; tar path checks do not explicitly validate link targets.
   The clean-install harness links into the template's existing prefix directory,
   apparently separating host state from its external Steam/marker checks; this is
   a source inference, not an executed failure. Wrapper replacement precedes
   final prefix/layout work. Timestamped rollback selection and bounded history
   correct the earlier UUID/literal-destination defects, but crash journaling and
   end-to-end recovery remain unvalidated.
   See [SECURITY](SECURITY.md) and [RUNTIME](RUNTIME.md).
2. **Release rollback contract:** backend rollback requires a published target even
   though newer publication supersedes it; an old signed payload does not create
   new downgrade authorization. Superseded appcast entries can fail download
   routes that require production records. See [RELEASE](RELEASE.md).
3. **Build/release evidence:** most toolchain locks are descriptive; the follow-up
   enforces FreeType's source checksum and adds architecture/recipe to engine keys.
   Keys still omit observed toolchain/applied-patch identity, uploads have no enforced immutability,
   and the recipe does not apply the referenced patch directory. Current CI
   does not run Swift/backend unit suites; runtime registration records
   `cleanInstall: not_verified` and GUI acceptance is not a release gate.
4. **Compatibility wiring:** inventory/registry paths still reference
   `SharedSupport/wine` while the current runtime uses `SharedSupport/engine`.
   Remote profiles and automatic post-failure renderer retry are not wired
   end to end. Stored renderer rollback does not fully restore named registry
   overrides. Renderer candidates are not installed/working capabilities.
5. **Commerce and licensing:** implement fulfillment before claiming delivery;
   exercise concurrent one-device activation and challenge/deactivation races.
   Public artifact routes are not entitlement gates. See [LICENSING](LICENSING.md).
6. **Operational boundaries:** no live service result is available. The backend
   image omits dev dependencies while API predeploy calls the Prisma CLI declared
   there; actual CLI availability/migration needs evidence. A log-only cron is
   not reconciliation. Package app can optionally upload dSYM if Sentry is configured.
7. **Privacy:** main app logs have redaction/rotation, but runtime-host logs lack
   rotation, raw game-attempt JSON can hold paths, and backend/landing raw errors
   bypass some sanitizers. A stated privacy policy is not a retention job.
8. **Acceptance milestone:** after the above contracts are reviewed, validate a
   specific signed/notarized app with a specific authenticated runtime in a fresh
   account: install, update/relaunch, activate license, install Steam, interact,
   run a control game and recover while preserving data.

These are source findings and missing evidence, not demonstrated exploits or
permission to change code/infrastructure in this audit.

## Historical evidence retained, not reverified

| Original report                                                                            | What it recorded                                                                                                                                                               | How to interpret now                                                                                                          |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Former DEVELOPER_GUIDE, 2026-08-20                                                         | Runtime 0.1.6, build 32325605325-1, signed private-storage publication and a responding API                                                                                    | Historical report only; no current release, object or health inference. Original at audited commit in Git history             |
| [BOOTSTRAP_VALIDATION](BOOTSTRAP_VALIDATION.md), local 2026-09-04 / UTC 2026-09-05 session | 110 passing desktop tests plus a skipped probe, later information-only installed Sparkle probe, five host tests, signed/notarized candidate and fixture relocation/replacement | Self-reported prior-session evidence; generated logs, Apple receipts and installed artifacts were not inspected in this audit |
| Same bootstrap report                                                                      | Engine fetch stopped without storage configuration; no clean Steam/game test, no normal/critical update fixture, real admin prompt unproven                                    | Preserve these explicit limits; candidate signing does not establish customer rollout                                         |

The earlier report's candidate versions and ignored artifact locations remain
historical context. No current filesystem or service condition is asserted from them.

## Commands executed during this audit

| Command / local check                                                                                   | Result and scope                                                                                                    |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `git rev-parse --show-toplevel`, `git status --short --branch`, `git rev-parse HEAD`                    | Root confirmed; clean starting tree and commit recorded above                                                       |
| Local UTC clock                                                                                         | Audit started 2026-09-05 01:51:44 UTC                                                                               |
| `git ls-files`, `rg --files`, `rg -n`, `cat`, `sed`, `git log` and selected `git show`                  | Mapped owned Markdown, applications, tests, scripts, workflows/configuration and decision history; no fetch/network |
| `./scripts/validate-production-policy.sh`                                                               | Passed                                                                                                              |
| `./scripts/build-runtime/source-audit.sh`                                                               | Passed required-input presence                                                                                      |
| `./scripts/build-runtime/resolve-engine.sh`                                                             | Passed; derived `wine-Wineversion11.16-8da89f8493b2`; does not prove stored engine existence                        |
| `./scripts/build-runtime/validate-manifest.sh docs/runtime-manifest.json`                               | Exit 1 as expected: blocked, zero components, no signature                                                          |
| `./scripts/build-runtime/validate-manifest.sh apps/backend/manifests/runtime-manifest.json`             | Exit 1 as expected for the same blocked-fixture conditions                                                          |
| Local Python read-only checksum calculation matching snapshot_checksum.sh's path/content/link algorithm | All six snapshots match lock; 12,597 files, no symlinks; no vendor modifications                                    |
| `sh -n` via local file-list loop; Python JSON/plist parsing                                             | 35 shell/hook, 18 JSON/resolution, five plist/entitlement files passed                                              |
| `actionlint .github/workflows/*.yml`                                                                    | Passed; no workflow dispatch/execution                                                                              |
| Documentation formatter, link/source-reference and sensitive-pattern checks                             | Passed; see documentation validation below                                                                          |
| `git diff --check`, `git diff --stat`, final path/status inspection                                     | Passed; see documentation validation below                                                                          |

Full Swift/backend/landing suites, dependency installation, Wine/runtime build,
signing, notarization, clean-install, game, Sparkle install and rollback were not
executed. They would create excluded generated outputs or require GUI,
certificates, user data or external services. This task changed documentation only.

## Documentation validation

- Reviewed all 53 repository-owned Markdown files; 52 changed (12 new, 40 updated).
  The project-supplied Sikarugir authorization statement is preserved unchanged.
- Checked 664 relative links, including local anchor targets, with no missing
  targets. Checked 37 script-path spellings, 87 inline source references and
  seven named npm/Bun scripts against the checkout/package definitions.
  External URLs were not fetched.
- Used the already installed landing Prettier executable: the initial check
  identified formatting issues in 21 files; formatted only the explicit set of
  52 changed Markdown files. The final check passes. No formatter configuration
  or dependency was changed and no repository-wide write command was used.
- Personal-path/private-key/token/credential-URL pattern scans and manual review
  found no secrets or personal paths introduced in documentation.
- Root and six component AGENTS agree on preservation, English UI, generated
  inputs, production-only reality and explicit agent publication authority.
  Independent component reviews confirmed navigation from the root router to
  the applicable document, source entry point, invariant, test and status.
- `git diff --check` passes. Final path inspection contains only Markdown;
  `git diff --exit-code -- vendor` passes. No production code, workflow YAML,
  infrastructure/configuration, dependency, installed app or user data was changed.
  No file was written inside the excluded generated/snapshot directories.
- `git diff --stat` was reviewed for all 40 tracked edits; its normal output
  excludes the 12 new untracked documentation files, which were checked separately.
- No commit, push, merge, deploy, release, manifest promotion, service request
  or other external mutation occurred.

The index in docs/README.md records the disposition of every old document.
Useful historical validation is scoped to its original report; obsolete duplicate
recipes now route to canonical references. The largest staleness risks are future
bootstrap/release changes, service configuration, source locks and milestone
results; re-check their owners rather than treating this snapshot as live truth.

## Sikarugir installer and background setup — 2026-09-08 UTC

**Checkpoint committed:** `d4cccd72` preserves the initial adapter, following the
user's explicit request. Subsequent integration changes remain uncommitted.
No push, workflow dispatch, deployment or publication was performed.

**Implemented but not end-to-end validated:** the three-archive installer now
accepts the approved original Sikarugir composition, verifies archive bytes before
replacement, preserves the fixed external prefix and installs the original engine
layout. Runtime workflow input transfer, provenance, component signing and native
installation gates are integrated while retaining the same-commit CI/release chain.
See [SIKARUGIR_INSTALLATION](SIKARUGIR_INSTALLATION.md) for the exact contract.

The user reported an upstream installer appearing during the experimental
external-prefix environment control. That control was stopped. Background setup
now rejects interactive winetricks configuration, and normal opening requires a
prepared external prefix and Steam executable before invoking Sikarugir. The
reported dialog itself was not captured, so its precise origin remains Unknown.

**Verified, scoped:** actual new/existing installation took 40.716/34.033 seconds;
synthetic data and wrapper metadata were preserved, Run autostart was skipped,
x64/x86 controls returned 37/23, and quiet official Steam installation completed.
Individual strict native signature checks passed; the initial ad-hoc candidate
correctly remained ineligible for publication. This does not prove whole-wrapper
signing: the external mutable prefix failed a separate full-seal experiment.

**Graphical result:** a captured integrated Steam updater rendered text and
progress. Final login content and interaction remain unconfirmed in the integrated
fixture after Steam updated to client 1788652215. The earlier original-stock
rendered-login/checkbox evidence remains scoped to that session. No everyday
prefix, installed runtime, account, games or native Steam was modified.

**Checks:** desktop 159 tests (one optional signed-app probe skipped), host 24
tests, both Swift builds, 93 script tests, source/snapshot audits, shell/JSON
validation, actionlint and production policy passed. Signing and the final silent
fixture continuation are recorded below. No hosted Wine build was
started. Rosetta dependency and upstream command-policy limits remain explicit.

**Final graphical continuation — Verified, local fixture:** the integrated
Developer ID candidate completed official silent installation and Steam's update
to client 1788652215. Owned-window screenshots showed the complete login form,
then Remember me changing from checked to unchecked using targeted keyboard
input. No credentials were entered. The login appeared about 50 seconds after
the updated client started. This supersedes the unconfirmed integrated-login
observation above, but does not establish customer installation or gameplay.
Only fixture processes were stopped; the preservation marker remained intact.
Exact archive bindings and screenshots' scope are recorded in
[SIKARUGIR_INSTALLATION](SIKARUGIR_INSTALLATION.md); images remain outside Git.

**Final signature/native acceptance — Verified, scoped:** corrected inline
`codesign -R` syntax now evaluates the intended Developer ID requirement rather
than treating it as a filename. Both actual entry signatures passed. A new archive
build and real installer probe passed strict verification of all five native
components, both Developer ID requirements, new/existing prefix preparation in
40.576/35.121 seconds, marker/metadata preservation and expected x64/x86 exits.
The newly signed archive did not receive a second graphical run; the successful
GUI control used the preceding signature instance of the same runtime source.
All 93 script tests passed after the attestation fix. Local builds record the
checkpoint plus uncommitted integration work, not an executed CI release.

**Final review:** 93 script tests, actionlint, production policy and `git diff --check`
passed after the final workflow/documentation review. Known integration fixtures
were stopped using exact prefix/executable ownership; their synthetic data was retained.

## Authorized release handoff — 2026-09-08 UTC

The owner explicitly requested committing and pushing the integrated Sikarugir
changes to generate the automatic release. The outgoing change includes the
verified local login/interaction and prefix-preservation work above. Existing
CI and runtime completion for the same commit remain prerequisites; this entry
is authorization and local evidence, not a claim that publication has completed.

## Live 0.1.36 migration follow-up — 2026-09-08 UTC

**Verified live failure:** the installed desktop reported version 0.1.36.
At 19:31:35 UTC, runtime replacement failed with `Sikarugir must remain the
runtime application entry point`; Steam was not opened. Read-only inspection
found the failed 0.1.36 wrapper correctly configured with `CFBundleExecutable`
set to `launcher` and `integration: sikarugir`. The app's recovery restored the
0.1.35 direct-Wine wrapper. No direct edits were made to the user's installed
app, runtime or everyday prefix during this investigation.

**Proven regression:** an isolated test retained a Foundation `Bundle` for the
legacy wrapper, installed the new archives at that same URL, and reproduced the
exact rejection. `Bundle.executableURL` retained `PortsideRuntimeHost` while the
fresh runtime configuration identified Sikarugir. Earlier native checks covered
new prefixes and Sikarugir-to-Sikarugir replacement, which kept the same entry
point; they missed this legacy-to-Sikarugir transition in a running desktop.

**Implemented correction:** mutable runtime resolution now reads current
`Info.plist` bytes with Foundation property-list parsing. Identifier, regular-file,
size, executable-name, contained-path and executable checks remain enforced.
Immutable embedded desktop helpers continue using Foundation Bundle resolution.
Tests cover the actual old/new directory replacement, rollback, preserved
synthetic data and replaced invalid metadata despite a cached valid bundle.
The native installation probe now primes synthetic legacy Bundle metadata before
installing the real runtime. Publication requires that migration check to pass.

**Validation:** the original regression failed before the correction and passed
afterwards. Desktop 161 tests (one optional probe skipped), host 24 tests, both
Swift builds, 93 script tests, source/snapshot audits and production policy passed.
Native migration acceptance is recorded in the continuation below. This is an
installation-migration fix; it does not invalidate the earlier rendered-login
fixture evidence or establish a new live graphical session.

**Native continuation — Verified:** using the existing signed 0.1.36 runtime
archives and the corrected desktop core, the synthetic cached-legacy transition
completed in 41.763 seconds and the existing-prefix pass in 33.786 seconds.
Markers and wrapper metadata were preserved, Run autostart was skipped, x64/x86
returned 37/23, and native signatures plus Developer ID requirements passed.
The fixture was stopped by its exact wineserver/prefix and removed. No Steam
installation or new graphical run was performed in this maintenance-only control.
The previously authorized integration release handoff also covers the corrective
commit/push; live customer migration still requires the corrected app release.

## Remove redundant runtime completion trigger — 2026-09-08 UTC

**Verified cause:** runtime run 37 (`34265050548`) was triggered by completion
of the engine workflow for `d95332e6`. Its preparation job succeeded while native
assembly and publication were skipped. It consumed the workflow counter between
published runtime 36 and the subsequent push build 38. Run 39 repeated that
redundant completion event for `c3fbc983`.

**Implemented:** at the owner's request, runtime assembly now triggers only on
relevant main pushes or explicit main dispatch. Removed the engine event branch,
its API request and event-only variables. Runtime naming, concurrency and all
checkouts use the triggering commit. Automatic release still checks CI and
runtime publication for the same source; no publication gate or version counter
was removed. Historical release-evidence compatibility remains available.

**Validation passed:** all 93 script tests, actionlint, shell syntax, production
policy and `git diff --check`. No app, Wine or installed-prefix change is
part of this workflow cleanup; no graphical retest is required for it.

## Release ticket lookup failure — 2026-09-09 UTC

**Verified failure:** [release run 34295188258](https://github.com/andre-fig/portside/actions/runs/34295188258)
for `4820ea24` passed its prerequisites, app build and signing. Apple accepted
the 0.1.40 ZIP submission at 00:31:49 UTC. At 00:31:51, stapling the app failed
with a CloudKit query error, a missing base64 ticket response and exit 65.
The script attempted stapling once; downstream publication was skipped. This
run did not publish app 0.1.40. **Unknown:** whether ticket propagation delay
or another CloudKit lookup problem caused the missing response; acceptance
alone does not establish that the ticket was retrievable.

**Implemented but not end-to-end validated:** app and DMG stapling now retry
that specific exit/message combination up to five times, with 5/10/20/40-second
delays. Submission rejection, unrelated stapler errors, exhausted retries and
ticket/signature/Gatekeeper validation failures still block publication.
Retries do not resubmit to Apple or change workflow prerequisites and triggers.

**Verified local controls:** five regression tests execute the real shell
orchestration with disposable synthetic artifacts and mock tools. They cover
app/DMG recovery without resubmission, persistent failure, unrelated errors,
rejected submissions and failed ticket validation. Actual Apple service recovery
and a completed release require a subsequent authorized production execution.
All 98 script tests passed with Python 3.14, as did actionlint, shell syntax,
`validate-production-policy.sh` and `git diff --check`. Swift builds and source
audits were not repeated because this change only affects release stapling,
its shell regression tests and documentation.
No installed app, runtime, user prefix or graphical Steam session was changed.
