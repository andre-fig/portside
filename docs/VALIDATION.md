# Validation plan and current status

The current environment is an Apple silicon Mac (`arm64`, Apple M4 Pro reported by MoltenVK) with Xcode 26.2. Rosetta is installed and passed `arch -x86_64 /usr/bin/true`.

## Automated status

`swift test` covers architecture/storage checks, secret and personal-data redaction, approved HTTPS origins, pinned manifest metadata, checksum rejection, safe archive paths, atomic installation, singular prefix layout, Codable setup phases, byte-based progress, silent argument construction, simulated non-zero installer exits, missing `steam.exe` validation, technical diagnostics context, and the absence of a game allowlist. The opt-in real test uses the actual runtime only when `PORTSIDE_REAL_INTEGRATION=1` is set.

## Automatic launch and diagnostics

The app starts setup from `PortsideApp.init` without an onboarding action. A valid persisted environment goes directly to the normal Steam launch path; an incomplete environment enters the single progress window and resumes idempotently. Failure is the only state with recovery actions.

`DiagnosticsService` keeps Sentry out of the core pipeline. Release configuration uses the supplied DSN, `sendDefaultPii=false`, zero tracing sample rate, no network breadcrumbs, no replay, no user object, a `beforeSend` allowlist, and a 30-event cache limit. Debug builds intentionally use no DSN. Manual diagnostics require an explicit confirmation and attach only a capped sanitized report. `scripts/package_app.sh` creates `build/Portside.app.dSYM`; upload is optional and requires an external `sentry-cli` plus `SENTRY_AUTH_TOKEN`.

## Runtime pipeline

The provider downloads Wine Staging 11.15 and GStreamer 1.28.5 from fixed HTTPS URLs, verifies SHA-256, resumes `.part` downloads, rejects unsafe tar paths, installs the runtime atomically under `Runtime/<version>`, uses WineD3D for Direct3D 9/10/11, and initializes `Prefix/Steam` idempotently. The GStreamer package is extracted locally with `pkgutil --expand-full`; no Homebrew or system framework installation is required.

## Silent Steam installation

The app invokes Wine through `Process` with an argument array equivalent to:

```text
<Portside Runtime>/Contents/Resources/wine/bin/wine <Portside Downloads>/SteamSetup.exe /S
```

`/S` is a separate, case-sensitive argument. The process receives `WINEPREFIX`, `WINEARCH=win64`, `WINEDEBUG=-all`, and the private GStreamer paths. No shell, Terminal, AppleScript, or user-visible installer process is used. Afterward, the app validates an executable `steam.exe`, runs the bootstrap equivalent of `steam.exe -silent`, waits for the client marker, and launches `steam.exe` normally.

## Wine crash-window handling

The Wine prefix is configured with `HKCU\\Software\\Wine\\WineDbg\\ShowCrashDialog=0`, and Portside-owned Wine processes receive `WINEDLLOVERRIDES=winedbg.exe=d` plus `WINEDEBUG=-all`. If a debugger process is nevertheless detected, readiness fails quickly, the failure is logged, and the supervisor requests shutdown of only the Portside prefix. This prevents an unresponsive Wine Debugger or generic Wine crash dialog from being left open by setup. The current prefix was updated with this registry value successfully.

## Real setup evidence

- Wine 11.15 downloaded and verified at `~/Library/Application Support/Portside/Downloads/wine-staging-gcenx-osx64-11.15.tar.xz`; SHA-256 matched the manifest.
- Wine installed at `~/Library/Application Support/Portside/Runtime/11.15/Contents/Resources/wine/bin/wine`.
- GStreamer 1.28.5 downloaded and verified, then assembled privately at `~/Library/Application Support/Portside/Runtime/Dependencies/GStreamer.framework`.
- `wineboot -u` completed with exit code 0 in 21.35 seconds; the Steam prefix was created.
- Steam installer downloaded from `https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe`; observed size 2,380,800 bytes and SHA-256 `7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb`.
- After adding the upstream `/S` installer flag, Steam updated itself and real `steam.exe` plus multiple `steamwebhelper.exe` processes were observed. Steam logs reported “Atualização concluída, iniciando o Steam”.
- The updated `Prefix/Steam` path was exercised in a second real setup attempt. Steam’s updater again launched and downloaded its client manifest; the strict 30-second readiness check returned `steamProcessRunning`, while the current session still could not expose a verifiable on-screen window.
- The current silent-bootstrap attempt used the real `/S` installer runner and then `steam.exe -silent`. The 30-second bootstrap observation did not find `steam_client_win32.installed`; a real `Steam.exe` process was observed, but the final 20-second readiness check again returned `steamProcessRunning`. No installer UI or Terminal could be observed in this headless agent session, so the absence of a pre-login Windows window is not claimed as fully validated here.
- Login was not performed; no credentials were accessed or stored.

The strict window-observation pass remains externally blocked in this agent session: `screencapture` reported `could not create image from display`, and CoreGraphics could not produce a verifiable visible window. Therefore this run does not claim the final “window ready for login” criterion, even though the real Steam client and `steamwebhelper` processes started. A normal interactive GUI session must rerun the opt-in integration test to confirm the final window state.

## Real Steam validation

Pending on a configured test Mac with a licensed runtime:

- first-run setup and cancel/retry;
- Steam installation, login persistence, update, window focus, and safe termination;
- full-library access and install/update/validate/uninstall of a Windows game selected by the user in Steam;
- diagnostic export and repair without deleting game files.

## GunZ: The Duel — App ID 3139440

No result is declared yet. Record each of the 30 requested checkpoints separately with status (`success`, `failure`, `not applicable`, or `not tested`), evidence, duration, exit code, and sanitized observation. If anti-cheat prevents a valid session, do not bypass it; classify the result as `Blocked by anti-cheat` only after observing that real failure.

## Control game

Select and document a small, legal, free or demo Windows-only Steam title without kernel-level anti-cheat only if GunZ blocks before graphics/input/audio can be evaluated. The control title must be chosen during the real test run based on current Steam availability; it is not embedded in Portside.
