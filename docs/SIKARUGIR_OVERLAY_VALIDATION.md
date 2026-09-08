# Sikarugir launcher and renderer-overlay control — 2026-09-08

**Later result:** after the project owner withdrew the restrictions that stopped
the original-engine control, the [authorized retest](SIKARUGIR_RESTORE_VALIDATION.md)
verified rendered Steam login and checkbox interaction with Sikarugir 10.0_6.
The report below preserves the evidence and constraints of its earlier test.

**Verified controls; graphical failure persists.** This follows the
[historical control](SIKARUGIR_LEGACY_VALIDATION.md) and retains all preservation,
source-build, signing and sandbox constraints. Main remains at `a4a0b952` plus
uncommitted investigation changes. No commit, push or publication was requested
or performed in this continuation.

## Verified before rebuilding

A fresh disposable assembly used the checksum-verified Template 1.0.11 from the
historical control and Portside's local Wine 11.17 x86_64 archive, SHA-256
`30fad3f925bdb550cb584833bd43cd70978c628d1bf7ec85e33ff04379ed159b`.
Launcher and SDK component signature verification passed. This is a reference
experiment with the original upstream components, not a source-built commercial
wrapper or whole-bundle signing acceptance. No everyday prefix, runtime, account,
game, library or native Steam was copied or modified.

Sikarugir `WSS-wineprefixcreate` created the fresh prefix; optional-addon skipping
was enabled only for this preparation and restored afterward. The prefix was
moved to a private external fixture path, linked back into the wrapper, and given
a synthetic preservation marker. The original launcher then executed both x64
and x86 Windows controls successfully with Portside's engine. `WSS-winetricks
steam` installed Valve Steam using the original checksum-verified winetricks.

The new [console control](../scripts/build-runtime/probe-steam-command.c) creates
a synthetic child named `steamwebhelper.exe` through Windows `CreateProcessW`.
It reports fixed booleans and exit status without printing arbitrary command
lines or environments. It does not contain CEF or disable a browser sandbox.

| Same control, Windows x64 and x86 | Historical engine | Portside engine through Sikarugir |
| --- | --- | --- |
| Child arguments preserved | No | Yes |
| `--no-sandbox` appended | Yes | No |
| `--in-process-gpu` appended | Yes | No |
| `--disable-gpu` appended | Yes | No |
| Child/parent status | 42 / 42 | 0 / 0 |

The historical console control initially failed before execution because its
standalone engine could not find `libinotify.0.dylib`. Supplying the inspected
template's original Frameworks directory through its library search environment
enabled the control above. No engine binary was patched. The new pre-execution
guard rejects the known workaround in both kernelbase architectures; it is a
targeted regression check, not proof of a complete Chromium sandbox.

LaunchServices opened the new Sikarugir fixture with explicit private home
variables. Steam progressed from Win32 manifest `1769731672` to Win64 client
`1788652215` without the manual restart required in the historical engine test.
This is one observed updater sequence, not a guarantee about future updates.
The session's webhelper logs did not contain the forbidden sandbox switch.

After the user enabled screen recording for VS Code, macOS reported capture
authorized. A capture of the positively identified fixture window was taken and
visually inspected: **the login window was completely black**. The image remains
only in the disposable evidence directory. A later region capture was obscured by
unrelated foreground content and immediately discarded; it is not Steam evidence.
No account was used. WineD3D/GLES 3 and builtin Vulkan fallback failures reproduced.

## Missing renderer-selection contract

Changing only the fixture's documented `DXMT` setting to 1 still loaded Wine's
own `d3d11.dll` and `dxgi.dll`, as shown by the current launch's DLL trace. The
Sikarugir launcher contains `WINEDLLPATH_PREPEND`; the original engine's ntdll
contains support for it. The pinned Wine source and the Portside engine do not.
Wine's ordinary `WINEDLLPATH` searches after its own DLL directory and cannot
provide the same renderer override semantics.

The template contains DXMT v0.74 and its x64/x86 PE DLLs and Metal bridge. The
bridge advertises macOS 15.0, despite the template's lower general minimum.
It also carries an upstream build-machine install name for `winemac.so`; no
commercial dependency/provenance acceptance is inferred from these binaries.

## Implemented and locally validated source changes

The [Portside patch series](../upstream/patches/wine/README.md) implements ordered,
absolute `WINEDLLPATH_PREPEND` entries before Wine's normal builtins. Empty and
relative entries are ignored; unset input retains default search order. It does
not change Steam arguments, sandbox behavior, registry state or prefix DLLs.
The recipe applies checksum-verified patches to its source copy and binds the
patch inputs into both engine identity and local install-cache identity.

The native C function tests compile the actual patched function and verify its
search order. Patch tests reject wrong base identity, altered/unlisted inputs,
reapplication and vendor/external destinations. A full Wine build completed
locally with a separate output/cache; hosted workflows were not dispatched.
The verified patch list is retained in engine metadata/provenance and propagated
into runtime provenance and the Wine SPDX source information. Publication checks
reject disagreement between these inventories.

The existing launcher/SDK source and matching complete recipe remain unavailable
in the inspected public repositories. This engine work does not turn the
reference template into a Portside-produced commercial component.


## Rebuilt engine and controlled comparison

The final archive is `PortsideWineEngine-wine-Wineversion11.17-36b6a2cf679f-x86_64-eff02caa27d0.tar.xz`,
337,177,636 bytes, SHA-256
`aa4a5bd9209dcdce7a531e472859082809c2f16b22bb76e2a59a0eafa793b31a`.
The build applied patch SHA-256
`d9c01f85b72f0eee72b783d0bc3fcc719902ee4ef13128dc7d44ae161359de80`.
Archive extraction, matching ntdll hashes, Windows execution, deployment targets
and privacy checks passed. This is an uncommitted local investigation build,
not a qualifying same-commit CI receipt or a signed release candidate.

Successive controls used the same synthetic external prefix and updated Valve
client `1788652215`; snapshots of log offsets isolate each launch. DLL tracing,
feature-level probes and screenshots were recorded separately. No authentic
user prefix or credentials were imported. Each attempt was stopped by the exact
fixture Wine server/owned launcher, with Steam/helper file holders checked.

| Controlled change | Actual result | Graphical conclusion |
| --- | --- | --- |
| Original Portside engine, WineD3D | ANGLE D3D11 cannot obtain GLES 3; prior comparable device control exposes at most FL 9_3; builtin Vulkan fallback fails | Owned login-window screenshot is black |
| Same engine, only `DXMT=1` | Wine's own D3D11/DXGI still load; prepend contract is absent | Renderer selection did not change |
| Source-patched engine, `DXMT=1` | DXMT now loads; missing `winemetal.dll` yields import failure `c0000135` | Selecting the renderer alone is insufficient |
| Same patched engine, original template bridge provisioned in the disposable prefix | D3D11 creates devices through FL 11_1; Steam reaches DXMT but cross-process swapchain creation returns `E_FAIL` | Owned window screenshot is black; CEF reports `EGL_BAD_ALLOC` creating its window surface |
| Same candidate, Steam `-cef-disable-gpu` control | Steam recognizes `--disable-gpu-compositing`; builtin Vulkan SwiftShader fallback fails | No accepted fix |
| Same software control plus Steamwebhelper-specific native Valve Vulkan loader | ANGLE selects `egl-angle`/SwiftShader GLES 3, without the old injected sandbox/isolation switches | Owned screenshot is black; user explicitly confirms the window remains black |

The bridge DLLs were copied only into absent locations in this disposable
prefix, from the checksum-verified reference template, with hashes recorded.
This tests the missing dependency, not a production installation policy. It
must not become arbitrary DLL copying into customer prefixes. The standalone
D3D11 probe used an adjacent original bridge DLL and returned `S_OK` for requested
levels 11_1, 11_0, 10_1, 10_0 and 9_3. Device creation does not exercise window
presentation or Chromium process isolation.

The patched ntdll restores DLL search order, but Wine 11's
`find_builtin_without_file` does not generally admit an unprovisioned new PE
module into an existing prefix outside bootstrap. The missing bridge and the
cross-process presentation restriction are separate failures encountered after
the original renderer-selection defect was removed.

Current-run logs contain:

- DXMT: `CreateSwapChain: cross-process swapchain not supported yet`.
- CEF: `Could not create additional swap chains or offscreen surfaces, HRESULT: 0x80004005`.
- CEF: `eglCreateWindowSurface failed with error EGL_BAD_ALLOC`.

The reference DXMT v0.74 implementation explicitly compares the window owner's
process to the current process and returns `E_FAIL` when they differ. The same
restriction exists at the inspected newer DXMT commit corresponding to the
Template 1.0.15 version prefix. Thus an update to that reference alone is not
evidence of a fix. [DXMT v0.74 source](https://github.com/3Shain/dxmt/blob/cc59982abcf49b6e595b2e7c82fac46c2f3d2dc6/src/d3d11/d3d11_swapchain.cpp),
[newer inspected source](https://github.com/3Shain/dxmt/blob/4ddb20e54672c0cb56115ce80d6db1beef94ae28/src/d3d11/d3d11_swapchain.cpp).
Removing this guard or forcing CEF into one process is not an implemented fix.
Supporting this path requires correct cross-process window presentation.

The software/native-Vulkan variant proves that successful GLES initialization
alone does not resolve the black window. Its remaining presentation/compositing
cause is **Unknown**; fewer GPU messages are not acceptance evidence. The
experimental software flag is not part of the shipped defaults.

## Prefix and readiness regressions

The source-built host was also exercised with the rebuilt engine in a separate
disposable wrapper. New-prefix bootstrap returned 0 in 14.075 seconds. An existing
prefix update returned 0 in 6.119 seconds, retained the synthetic marker and did
not run a synthetic startup entry. Subsequent Windows x64/x86 controls returned
the expected 37/23. This confirms the prior controlled `wineboot -u -r` update
fix against real Wine; it does not validate arbitrary .NET applications.

Desktop diagnostics now also tail `cef_log.txt` for the explicit window-surface
failure above, separately from exhausted GPU initialization in
`webhelper_gpu.txt`. Both readers exclude prelaunch bytes, old/future timestamps,
symlinks, incomplete records and out-of-prefix paths, and bound each read. CEF's
yearless timestamps are resolved around launch, including a New Year transition.
A three-second grace allows another GPU attempt. Newer GPU starts supersede an
older failure across both logs; a GL capability report alone cannot clear a
presentation failure. No log event authorizes `ready`; rendered content and
interaction still require user confirmation. This monitor improves reporting,
not the renderer. An unlogged successful surface retry within the same GPU
process cannot be inferred from the available log format.

## Validation performed and remaining acceptance

Commands were run from the repository root with disposable output directories:

- `swift test --package-path apps/runtime-host` and `swift build --package-path apps/runtime-host`:
  16 tests passed and build passed.
- `swift test --package-path apps/desktop` and `swift build --package-path apps/desktop`:
  145 tests, one optional signed-app/network probe skipped, no failures; build passed.
- `python3.14 -B -m unittest discover -s scripts/tests -v`: 80 tests passed, including the actual assembly metadata recipe with synthetic
  archives (native build steps stubbed only in that regression test).
- `PORTSIDE_ENGINE_BUILD_DIR="$PWD/build/sikarugir-overlay-control" PORTSIDE_WINE_CACHE_DIR="$PWD/build/sikarugir-overlay-control/cache" PORTSIDE_ENGINE_PRODUCER=local-investigation PORTSIDE_BUILD_JOBS=10 ./scripts/build-runtime/build-engine.sh`:
  full local compile, execution/privacy checks and archive passed; a subsequent
  cached repackage included the final patch provenance.
- `validate-engine-execution.py` and `validate-engine-privacy.py` on a safely
  extracted final archive: passed; x64/x86 expected exits 37/23, no SIGKILL.
- Source-built `build-wrapper.sh`, `build-winetricks.sh` and the real-host
  `validate-host-bootstrap.py` controls described above: passed.
- Both MinGW architectures compiled `probe-steam-command.c` with
  `-municode -Wall -Wextra -Werror -O2`; the parent/child matrix above passed
  with the new engine and rejected the old injected arguments as expected.
- Source audit, Wine/winetricks snapshot validation, `actionlint`, applicable
  shell/JSON checks, `validate-production-policy.sh` and `git diff --check`: passed.

**Rendered interactive Steam: not achieved.** The final fixture was closed after
the user's black-window confirmation; its preservation marker remained intact
and no fixture Steam/helper file holders remained. No account login or positive
interaction acceptance occurred. No game compatibility is established.

**Blocked commercial Sikarugir migration:** matching Launcher/SDK source and its
complete build/configuration recipe remain unavailable in the inspected public
repositories. Those inputs, including renderer provisioning and dependency
provenance, are needed to produce Portside's own integrated components. The
reference binary experiment is not a substitute. Even with those inputs,
isolation-preserving presentation and the software path still need a verified
fix, followed by a signed/notarized matching app/runtime release and an actual
rendered, interactive Steam acceptance run. Signing or a release alone cannot
fix this observed black window.

Wine remains x86_64 via Rosetta on this Apple Silicon Mac. The Intel deprecation
notice was not hidden and is a future compatibility limitation; it does not
explain this measured presentation failure. The earlier ARM64 loader defect was
not revisited or declared resolved. No installed runtime or everyday prefix was
changed, and no workflow dispatch, new commit, push or publication occurred.
