# Portside validation

## Automated validation

Run:

~~~sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
cd apps/backend && npm run typecheck && npm run lint && npm test && npm run build
cd ../..
for file in scripts/build-runtime/*.sh scripts/generate_manifest.sh scripts/publish_runtime_staging.sh scripts/publish_release.sh scripts/promote_runtime_storage.sh; do sh -n "$file"; done
./scripts/validate-production-policy.sh
./scripts/package_app.sh
~~~

The current suite covers the Portside artifact catalog and checksums, native
engine selection, daily update throttling, baseline Info.plist values,
winetricks steam, clean wrapper launch arguments, archive traversal,
atomic installation, secret sanitization, renderer fallback ordering,
32/64-bit PE detection, process ownership, readiness states and manifest
round-tripping.

## Required graphical acceptance

The reproducible operator-assisted flow is
`./scripts/validate-clean-install.sh`, launched by the manual
`.github/workflows/validate-clean-install.yml` workflow. It must run on a
self-hosted Apple-silicon Mac with labels `self-hosted`, `macos`, and `arm64`,
logged into the desktop session that will receive the Dock/window. The
selected runner must have Accessibility permission for its runner account.
The workflow downloads the signed runtime artifact from a selected build run;
it does not consult an upstream URL or a native Steam installation.

The following must be checked on a real macOS display for the migrated Portside
build:

1. Rosetta is installed only when absent.
2. The first run creates a new isolated wrapper and runs the vendored
   winetricks `steam` verb.
3. The initial Steam updater finishes and its first execution exits.
4. The same wrapper opens cleanly a second time.
5. The wrapper appears in the Dock and creates a real Steam window.
6. The login page is visibly rendered, including fields and controls.
7. Mouse and keyboard input work in the login fields.
8. steamwebhelper remains running and Steam remains open after the updater.
9. After login, a test game can be downloaded, installed, launched and closed.
10. The required first game check is GunZ: The Duel, App ID 3139440; this does
    not imply that every Steam game is supported.

The script accepts `YES` only after each visual check is performed by the
operator. A missing signature, checksum mismatch, missing component or failed
process step fails the run. It stores only sanitized logs and a harmless
validation marker inside the disposable prefix. When a previous workflow
artifact is supplied, it replaces the wrapper while retaining the same prefix
and checks that marker before and after the replacement; the operator still
confirms the rollback/update behavior on screen.

GitHub Actions steps normally have no interactive TTY. In that case the script
opens the candidate wrapper, leaves it running, exits without claiming success,
and uploads the sanitized logs; the visual checks must then be performed from a
logged-in Terminal on the self-hosted Mac with the same artifact directory.

The automated monitor intentionally records only visibleButUnverified when it
sees a managed on-screen window. It never records uiReady from process
existence, Dock presence or steamwebhelper alone. A manual visual
confirmation must be recorded separately, without screenshots or account data.

## Failure stages

If the graphical check fails, preserve local logs and identify exactly one of:

~~~text
prefix creation
official winetricks installation
Steam updater
initial shutdown
second clean opening
window creation
rendered login UI
input interaction
Steam persistence after update
game compatibility
~~~

Logs are under the Portside Application Support Logs directory; diagnostics
are sanitized and do not include passwords, cookies, tokens, Steam IDs,
screenshots or full user paths.

## Completion matrix

| Acceptance item | Current evidence | Status |
| --- | --- | --- |
| Portside-owned wrapper and native host | local `build-wrapper.sh`, Mach-O host and Swift tests | SIM |
| Wine engine from vendored source | local source build, archive and clean-layout validation | SIM |
| Winetricks from vendored source | local archive and clean-layout validation | SIM |
| Three artifacts with checksums/provenance/SBOM | local unsigned manifest validation | SIM |
| Signed staging manifest and both buckets | requires CI signing/storage secrets and promotion records | BLOQUEADO |
| Production manifest and rollback publication | requires protected backend/storage promotion | BLOQUEADO |
| Clean prefix and official Valve Steam verb | script is ready; no acceptance run is claimed here | PENDENTE |
| Login window, field interaction and Steam persistence | requires the operator on a real GUI session | BLOQUEADO |
| Free control game launch | requires the operator after login | BLOQUEADO |

Only after the operator records `testResult.cleanInstall = "passed"` against the
successful build may the backend promote its staging release.

## Baseline evidence

The source/build checks above do not prove that Steam's graphical interface
works. The Portside runtime host and artifacts must be installed into a fresh
wrapper and the graphical acceptance list must be completed on the real Mac.
`interfaceVerification` remains `notVerified` until a person confirms the
rendered login form and keyboard/mouse interaction on the real display.
