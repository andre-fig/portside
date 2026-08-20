# Portside validation

## Automated validation

Run:

~~~sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
cd apps/backend && npm run typecheck && npm run lint && npm test && npm run build
cd ../..
for file in scripts/build-runtime/*.sh scripts/generate_manifest.sh scripts/publish_runtime_staging.sh; do sh -n "$file"; done
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

## Baseline evidence

The source/build checks above do not prove that Steam's graphical interface
works. The Portside runtime host and artifacts must be installed into a fresh
wrapper and the graphical acceptance list must be completed on the real Mac.
`interfaceVerification` remains `notVerified` until a person confirms the
rendered login form and keyboard/mouse interaction on the real display.
