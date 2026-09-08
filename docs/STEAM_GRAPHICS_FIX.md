# Steam graphics and prefix upgrade — 2026-09-07 UTC

**Direction corrected on 2026-09-08:** the project owner requires an automated
Sikarugir integration, including its launcher/SDK and component composition.
The direct-Wine candidate below is experimental evidence, not that integration.
See [SIKARUGIR_INTEGRATION](SIKARUGIR_INTEGRATION.md) for the inspected reference,
missing source/build inputs and remaining migration work.

**Implemented but not end-to-end validated.** Local changes start from
`0e5a5eb26dd972bc9b5a4a2a229a2a268d22a1a6`. The earlier uncommitted live
installation report in [STATUS](STATUS.md) is preserved. No everyday prefix,
installed runtime, native Steam, games, saves or credentials were used or changed.

**User-confirmed failure after the candidate:** the user reports that the open
Steam fixture is still entirely black. No screenshot was captured or inspected
in the preceding investigation because macOS reported screen capture unavailable.
The native-loader change fixes the measured SwiftShader initialization failure,
but does not establish a fix for Steam's visible interface. Further investigation
must cover CEF composition/presentation and actual window pixels.

## Reproduction and causal controls

**Verified, scoped:** Apple M4 Pro, macOS 26.6.2, Wine 11.17 x86_64 through
Rosetta. The selected local engine archive was checked against its producer
metadata: 337,106,284 bytes, SHA-256
`30fad3f925bdb550cb584833bd43cd70978c628d1bf7ec85e33ff04379ed159b`, Wine source
`36b6a2cf679fb395f668a917b76537190e212d9c`, recipe identity
`wine-Wineversion11.17-36b6a2cf679f-x86_64-fe553e2d62ce`.
This is controlled local build evidence, not fresh authentication of a live
production manifest or final distribution signing.

A new disposable home, wrapper and external symlinked prefix were prepared.
Valve's installer came from the checked-in quiet winetricks Steam verb with its
checksum verification. Bootstrap took 23.0 seconds and installation 72.15 seconds.
The first Steam invocation downloaded approximately 236,054 KB, updated itself
to client build `1788652215` (September 2 updater), and returned loader exit 42
while managed children continued. Its CEF reports identify Chrome 126.0.6478.183,
ANGLE 2.1.23105, commit `5d4df51d1d7d`.

The updated baseline reproduced the GLES/Vulkan/GPU initialization errors from
the live report. This is log reproduction; screen capture was unavailable and
the baseline's black pixels were not independently observed in this task.

| Control | Default loader | Native Vulkan loader for the probe / Steam web helper |
| --- | --- | --- |
| D3D11 device creation | Feature levels 11_1, 11_0, 10_1 and 10_0 fail; 9_3 succeeds | Unchanged |
| macOS backend | OpenGL 4.1, Apple M4 Pro; WineD3D maximum `0x9300` | Unchanged |
| Valve ANGLE D3D11 context | GLES 2 succeeds; GLES 3 fails with `EGL_BAD_MATCH` (`0x3009`) | Unchanged |
| ANGLE OpenGL backend | Initialization fails: GLES 2 is not supportable | No alternative OpenGL path adopted |
| ANGLE Vulkan / SwiftShader | Wine builtin `vulkan-1.dll` loads; Wine reports it was built without Vulkan; initialization fails with Vulkan -9 | Valve native `vulkan-1.dll` loads its `vk_swiftshader.dll`; GLES 2 and GLES 3 contexts succeed |
| Offscreen rendering with Valve ANGLE | No SwiftShader context | RGBA readback `64,128,191,255` matches the requested clear color in both context controls |
| Steam CEF report | Repeated GPU initialization failures and exhausted SwiftShader fallback | `(gl=egl-angle,angle=swiftshader)`, Vulkan 1.3.0, SwiftShader driver 5.0.0 |

Wine's `dlls/wined3d/adapter_gl.c:feature_level_from_caps` explains the capability
selection. The extension trace includes `GL_ARB_sampler_objects` but no
`GL_ARB_polygon_offset_clamp` or `GL_EXT_polygon_offset_clamp`; the source's
feature-level-10 gate requires polygon-offset-clamp support. It is not safe to
advertise higher capabilities merely to satisfy CEF.
The default Wine DLL loader substitutes its builtin Vulkan loader even
when ANGLE requests Steam's local loader. A native-loader control without
selecting SwiftShader still fails because native GPU Vulkan is unavailable.
Selecting Valve's native loader **and allowing ANGLE's existing SwiftShader
fallback** supplies the missing working path. Vulkan result -9 is an API error,
not the earlier Darwin SIGKILL 9.

The candidate was first tested with an app-specific registry change inside the
disposable prefix, then repeated using a wrapper compiled from the corrected
host source. That second run used a separate copy of the synthetic updated
baseline, retained its preservation marker and verified identical hashes of
`steam.exe`, `libEGL.dll`, `libGLESv2.dll`, `vulkan-1.dll` and `vk_swiftshader.dll`.
Source-host preparation completed in 11.990 seconds. Steam found the same
installed update and selected SwiftShader again. D3D11's initial GLES error
still appears before successful fallback: removing every error line is not the
acceptance criterion. Observed helper command lines contained none of the
sandbox-disabling switches checked in this investigation.

## Source changes

The desktop installer now runs controlled prefix preparation for **both new and
existing prefixes**, including retries after interrupted initialization. It
relinks the wrapper entry without removing the external prefix. Preparation
runs per runtime installation/repair, not every Steam opening.

The host's existing `--create-prefix` command runs `wineboot -u -r`, deferring
`mscoree`/`mshtml` only in that subprocess. On success it configures:

```text
HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides
vulkan-1 = native,builtin
```

The `-r` option skips Run/Startup programs without terminating processes. Source
inspection found that plain `-u` executes those programs on an existing prefix,
potentially starting Steam before preparation has completed. The fixture now
registers a synthetic startup command and checks that it is not executed.

The registry command runs without the temporary addon suppression. Either
operation's failure fails preparation. This app-specific policy is persistent;
the Mono/Gecko overrides are not. Games and other executables retain normal
Wine Vulkan/DLL selection. No Steam launch flags, sandbox/driver security
exceptions, downloaded replacement DLLs or new runtime dependencies are added.
Valve continues to supply and update its own CEF, loader and SwiftShader files.

This enables software rendering for Steam's interface fallback. It can cost CPU
time and power and does not add GPU Vulkan support or improve game compatibility.
WineD3D remains the game baseline. A future Steam/CEF update can change loader
behavior or remove the bundled software driver and requires renewed acceptance.

The desktop keeps `visibleButUnverified` in a visible verification step. It asks
the user to confirm rendered content and interaction or report a blank window.
Only confirmation can record `manualConfirmed`/`uiReady`, complete setup and
close the launcher. The installed-environment screen no longer claims that
Steam is ready to play. While confirmation is pending, it monitors owned Steam
processes and current renderer diagnostics. Reopening Portside after an
unconfirmed launch reuses the installed environment; only an explicit repair
clears that launch evidence and repeats installation.

Renderer diagnostics snapshot `webhelper_gpu.txt` before launch and read bounded
new bytes with current-session timestamps. Old records, partial lines, symlink
logs and isolated EGL errors do not establish a failure. An explicit exhausted
GPU initialization report is considered after a three-second recovery grace;
a newer GPU start or initialized ANGLE report clears it. This is a diagnostic
signal, never positive proof of UI rendering.

## Validation and remaining acceptance

**Verified:** the final corrected host created a fresh prefix in 15.601 seconds,
updated that existing prefix in 7.520 seconds, preserved its synthetic marker,
exposed the intended CEF registry policy, and executed x64/x86 commands with
expected exits 37/23. Fixture tests cover both installer branches, interrupted
retry, nonzero preparation, app-scoped configuration, addon environment isolation,
current/old/recovered GPU records and refusal to authorize graphical handoff
from window/process metadata.

The original host failed the added autostart control: plain `wineboot -u`
executed the synthetic Run command. The final `-u -r` host passed the same
control and removed the synthetic registration before continuing validation.
Sixteen host tests and both Swift builds passed. The final desktop suite ran
139 tests, with one optional signed-app probe skipped and no failures. Earlier
full runs hit EPERM reading a protected Sparkle test receipt; the isolated test
and final complete suite passed without altering file protection. All 65 script
tests, source/snapshot audits, production policy, workflow lint and whitespace
checks passed. No heavy Wine build or backend/landing tests were needed.

Commands used from the repository root:

```sh
swift test --package-path apps/runtime-host
swift build --package-path apps/runtime-host
swift test --package-path apps/desktop
swift build --package-path apps/desktop
python3.14 -B -m unittest discover -s scripts/tests -v
./scripts/validate-production-policy.sh
./scripts/build-runtime/source-audit.sh
./scripts/upstream/validate_snapshot.sh vendor/wine
./scripts/upstream/validate_snapshot.sh vendor/winetricks
actionlint .github/workflows/*.yml
git diff --check
```

`build-wrapper.sh` produced separate baseline and candidate wrappers with
explicit output directories. `validate-steam-bootstrap.py WRAPPER ENGINE
WINETRICKS` now exercises new and existing prefixes and the CEF policy. Optional
`--install-steam --observe-steam` installs Valve Steam and opens its disposable
fixture for manual inspection. The observation interval alone never passes GUI
acceptance.

The diagnostic sources `scripts/build-runtime/probe-d3d11.c` (link `-ld3d11`)
and `probe-steam-angle.c` compile with `x86_64-w64-mingw32-gcc`. Run only with an
explicit disposable `WINEPREFIX`/home and the selected fixture engine. The ANGLE
probe takes the fixture's Windows CEF directory and backend `0x3208` (D3D11),
`0x320D` (OpenGL) or `0x3450` (Vulkan); a fourth argument selects SwiftShader.
Compare default selection with `WINEDLLOVERRIDES=vulkan-1=n` **for the probe
process only**. Do not export that override for Steam or games. Synthetic pixel
readback verifies the renderer without capturing the user's desktop.

**Blocked graphical acceptance:** macOS reported screen capture unavailable;
Accessibility/window metadata is available but cannot prove rendered pixels.
The operator subsequently confirmed that the candidate Steam window remains
black. Rendered interactive acceptance has therefore failed. No login, account data or game acceptance
was attempted. A healthy CEF report and the offscreen pixel control do not
establish complete Steam acceptance.

Rosetta remains required. Apple's [support guidance](https://support.apple.com/en-ca/102527)
describes general availability through macOS 27 and restricted legacy-game
functionality from macOS 28. The Intel notice is not suppressed. No ARM64 loader
reversion, new Wine build, hosted compilation, publication or security-policy
change occurred. Shipping requires a newly authenticated runtime and signed app
release plus final installed GUI acceptance; current installed 0.1.35 was untouched.
