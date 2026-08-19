# Portside validation

## Current product contract

Release has one runtime and one launch path:

```text
Gcenx Wine Staging 11.6_1
  -> private Prefix/Steam
  -> SteamSetup.exe /S (first installation only)
  -> steam.exe with no launch flags
```

The runtime archive is downloaded from the pinned HTTPS URL in `docs/runtime-manifest.json`, checked for the pinned size and SHA-256, and installed atomically. Existing prefix data is not removed. A `Backups/Steam-prefix-*` snapshot is retained before prefix initialization or a runtime transition; failed transitions restore the snapshot and retain the failed prefix for recovery.

Portside does not install, open, wait for, copy data from, or uninstall native macOS Steam. It does not copy `config`, `registry.vdf` or `userdata`. It does not use the old CEF flags, `-no-browser`, GPU fallbacks, ESYNC cascade, shell commands, Screen Recording APIs, D3DMetal, GPTK or a SteamHost wrapper.

## Automated checks

Run:

```sh
swift test
swift build
./scripts/package_app.sh
```

The test suite covers:

- the single pinned Wine 11.6_1 runtime, URL, size and checksum;
- absence of native-login state and experimental Steam arguments;
- installer-only `/S` arguments, separate `Process` elements and no shell;
- official Wine environment without legacy ESYNC variables;
- the development-only Sikarugir reference environment (`WINEMSYNC=1`, `WINEESYNC=0`);
- requiring real `msync: bootstrapped` and `msync: up and running` log lines;
- prefix snapshot/restore while preserving `steamapps` and user data;
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

The packaged app was exercised on 2026-08-19 against the existing Portside prefix. Wine Staging 11.6_1 passed the pinned checksum and extracted successfully; `steam.exe` launched with no experimental arguments, five managed `steamwebhelper` processes were observed, and Portside closed after the stable handoff. The helper command line reported `cef.win64` and `en-US`. This confirms runtime selection and process handoff only; it is not visual confirmation that the login page is rendered or that the black-screen issue is fixed.

On a real display, verify manually:

1. setup completes and opens only the managed Windows Steam process;
2. the login page shows text, fields, QR code and buttons rather than a uniformly black surface;
3. mouse and keyboard input work;
4. the Steam library renders after login;
5. Steam remains open after Portside exits and still renders after a Steam restart;
6. opening Portside twice does not create another managed Steam tree;
7. closing Steam through the normal UI or Portside’s stop action terminates only the Portside prefix.

Until those checks are performed on a display, the black-screen issue remains unconfirmed. Process existence, `steamwebhelper` presence or a browser-ready log line alone must not be reported as visual success.

## Diagnostics

Setup and launch failures are captured automatically by Sentry with sanitized fields for runtime, process type, exit code, helper lifecycle, managed window handoff and verified MSYNC log markers. Credentials, account names, Steam IDs, cookies, tokens and file contents are not sent. Full logs remain local in `~/Library/Application Support/Portside/Logs`.
