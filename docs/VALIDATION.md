# Portside validation

## Current product contract

Release has one runtime and one launch path:

```text
Gcenx Wine Staging 11.6_1
  -> private Prefix/Steam
  -> SteamSetup.exe /S (first installation only)
  -> steam.exe -udpforce -noreactlogin -allosarches -cef-force-32bit
```

The runtime archive is downloaded from the pinned HTTPS URL in `docs/runtime-manifest.json`, checked for the pinned size and SHA-256, and installed atomically. The prefix stores `.portside-runtime.json` with the runtime that prepared it. A `Backups/Steam-prefix-*` recovery point is created before a runtime transition; APFS clonefile is preferred and the fallback captures only Wine registry/link state, never `steamapps` or caches. A failed transition runs rollback, and successful migration retains at most one recovery point.

Portside does not install, open, wait for, copy data from, or uninstall native macOS Steam. It does not copy `config`, `registry.vdf` or `userdata`. It does not use `-no-browser`, GPU fallbacks, ESYNC cascade, shell commands, Screen Recording APIs, D3DMetal, GPTK or a SteamHost wrapper.

## Automated checks

Run:

```sh
swift test
swift build
./scripts/package_app.sh
```

The test suite covers:

- the single pinned Wine 11.6_1 runtime, URL, size and checksum;
- absence of native-login state and preservation of the ordered Steam login arguments;
- installer-only `/S` arguments, separate `Process` elements and no shell;
- official Wine environment that removes inherited synchronization and experimental graphics variables;
- the development-only Sikarugir reference environment (`WINEMSYNC=1`, `WINEESYNC=0`);
- requiring real `msync: bootstrapped` and `msync: up and running` log lines from the process log, not `ps` output;
- 11.15 → 11.6_1 metadata migration, `wineboot -u`, rollback and obsolete-runtime cleanup;
- targeted snapshot/restore, APFS clone preference, no `steamapps` copy and retention of one recovery point;
- process handoff without false window/UI readiness and rejection of external Steam helpers;
- safe archive extraction, checksum rejection, atomic install and duplicate-launch locking;
- sanitized technical diagnostics.

## Runtime comparison

The official Gcenx Wine Staging 11.6_1 asset is the only Release runtime. The Sikarugir candidate is not bundled or selected: the project did not expose a verifiable official binary release for `WS12WineSikarugir10.0_6`, and the Sikarugir repository distinguishes its closed/restricted runtime components from the LGPL source distribution. No claim is made that Sikarugir was executed locally.

If a separately authorized Sikarugir build is supplied for development, validate it in an isolated prefix with the exact environment:

```text
WINEMSYNC=1
WINEESYNC=0
```

Record `msync: bootstrapped` and `msync: up and running` from the actual Wine output. Environment variables alone are not evidence that MSYNC is active. Do not add a second runtime or fallback path to Release.

## Interactive validation status

The automated checks can prove download integrity, process ownership and a stable `steam.exe`/`steamwebhelper` handoff. They cannot prove that the login page is rendered or that it is not black. Portside deliberately does not capture another app’s pixels and therefore does not request Screen Recording permission.

The corrected packaged app was exercised on 2026-08-19 in the interactive macOS session. The existing prefix was migrated with `wineboot -u`, `.portside-runtime.json` was written for Wine 11.6_1, one APFS recovery point was retained, and the old 11.15 runtime directory was not selected. The run launched `steam.exe` with the four ordered arguments, identified six `steamwebhelper` processes through Portside-prefix file evidence, and Portside exited while Steam remained running. This confirms process handoff and process survival only. `window_detected=false`, `interface_verification=not_verified`, and no visual confirmation of the login page was made by the agent. The helper still reported `cef.win64` and the CEF log still contains the EGL/GLES context errors, so the black-screen issue remains unresolved/unconfirmed.

On a real display, verify manually:

1. setup completes and opens only the managed Windows Steam process;
2. the login page shows text, fields, QR code and buttons rather than a uniformly black surface;
3. mouse and keyboard input work;
4. the Steam library renders after login;
5. Steam remains open after Portside exits and still renders after a Steam restart;
6. opening Portside twice does not create another managed Steam tree;
7. closing Steam through the normal UI or Portside’s stop action terminates only the Portside prefix.

Until those checks are performed on a display, the black-screen issue remains unconfirmed. Process existence, `steamwebhelper` presence or a process-handoff log line alone must not be reported as visual success. `window_detected` remains false unless an independent manual/UI validation is recorded.

## Diagnostics

Setup and launch failures are captured automatically by Sentry with sanitized fields for runtime, process type, exit code, helper lifecycle, process handoff and verified synchronization log markers. Window/UI fields are not asserted by the process monitor. Credentials, account names, Steam IDs, cookies, tokens and file contents are not sent. Full logs remain local in `~/Library/Application Support/Portside/Logs`.
