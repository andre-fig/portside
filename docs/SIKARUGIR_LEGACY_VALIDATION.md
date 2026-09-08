# Historical Sikarugir control — 2026-09-08

**Later result:** after the project owner withdrew the restrictions that stopped
the original-engine control, the [authorized retest](SIKARUGIR_RESTORE_VALIDATION.md)
verified rendered Steam login and checkbox interaction with Sikarugir 10.0_6.
The report below preserves the evidence and constraints of its earlier test.

**Test executed; graphical acceptance not established.** The project owner
authorized committing the current investigation and testing the historical
Sikarugir integration. Commit `a4a0b952` preserves the preceding changes,
including the previously uncommitted live 0.1.35 report. No push occurred.
A separate detached worktree at `8e9eda9e19c0fee06a20b4e8b2ce2781cb62dab6`
preserves that historical source without reverting the main checkout.

## Source, isolation and artifact checks

The historical `PortsideCore` was built unchanged. A temporary harness linked
against its object files and called `SikarugirWrapperInstaller.install` and
`SikarugirSteamFlow.installationSpec`. Its private home and Application Support
resolution were checked before any installer writes. LaunchServices received
explicit fixture HOME/CFFIXED_USER_HOME values to isolate the test. The ordinary
desktop app was built and tested, but its production account/update flow was
not opened against the everyday environment.

| Historical input | Verified SHA-256 |
| --- | --- |
| Template 1.0.11, 84,533,420 bytes | `9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a` |
| WS12WineSikarugir10.0_6, 166,304,096 bytes | `9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2` |
| winetricks at `5a59ea07513b24093bd90fad943ecf9543cf05bc`, 849,574 bytes | `f35c29737ca08a583569e6a3752d52fbe23333c5acfad5f16c4177d25eaf3f4b` |

All inputs came from the historical catalog's official URLs. The harness also
ran that revision's artifact and integrity validators. No installed runtime,
everyday prefix, credentials, games, saves or native Steam were copied or changed.

## Observed sequence

1. Historical desktop `swift test` passed 25 tests; `swift build` passed.
2. `WSS-wineprefixcreate` completed with status 0. Two Wine Mono dialogs appeared
   and were cancelled using input directed only to the fixture-owned processes.
   The installer moved the fresh prefix outside the wrapper, established the
   symlink and retained a synthetic preservation marker.
3. `WSS-winetricks steam` installed Valve Steam and completed with status 0.
   Its normal checksum verification and font installation ran. No advertised
   sandbox-disabling workaround from winetricks' warning text was supplied by
   the harness.
4. The first LaunchServices opening requested Win32 client manifest version
   `1769731672` and downloaded approximately 336,229 KB. The log recorded
   `Failed to determine download location for universe 1`; Accessibility later
   identified a `Steam - Fatal Error` window. Its body was not read, so the
   precise fatal condition is unknown. That generic log line alone does not
   establish the cause.
5. A controlled restart preserved the downloaded files and prefix marker.
   It used the exact fixture wineserver with an explicitly checked WINEPREFIX,
   never a global process-name kill. The next opening progressed through the
   Win32 update and fetched Win64 client `1788652215`, approximately 236,054 KB.
   This matches the final client build in the 0.1.35 graphics investigation;
   comparing the initial updater alone would compare different clients.
6. The Win64 webhelper started with `--no-sandbox --in-process-gpu --disable-gpu`.
   Its GPU log recorded `Disabling GPU acceleration: Disabled/CommandLine`.
   The test was stopped when this was identified because sandbox-disabling
   flags remain outside the authorized solution. No rendered/interactive Steam
   acceptance was recorded. Cleanup used only positively identified fixture
   launchers and the prefix-scoped wineserver; no Steam/webhelper process held
   the fixture executables afterward.

## Engine workaround evidence

The historical Portside baseline has empty Steam program flags and disables
DXMT/DXVK/D3DMetal. Its bootstrap log shows ordinary Steam invocations without
the CEF switches. The engine's x86 and x64 `kernelbase.dll` files contain the
UTF-16 `steamwebhelper.exe` entry and the exact appended string
` --no-sandbox --in-process-gpu --disable-gpu`, adjacent to other application
workarounds and the `hack_append_command_line` diagnostic name.
The observed webhelper command matches this engine compatibility behavior.

Both DLLs were compared byte-for-byte to members read directly from the
checksum-verified original engine archive:

| Engine member | SHA-256, identical to downloaded member |
| --- | --- |
| `lib/wine/i386-windows/kernelbase.dll` | `1f3ede331fc50a9fd963487747ec6f4383beecb89dc89e8417288247f506e921` |
| `lib/wine/x86_64-windows/kernelbase.dll` | `5849f8a94440abe9e8f67bc5bf180fb9465946e92144a5bf850010633a0a39bf` |

This is binary inspection plus observed execution, not an audit of the matching
engine's source recipe. No DLL was patched to remove these strings. It identifies
a material difference from the 0.1.35 controls; it does not prove that disabling
the sandbox caused the earlier user-reported success or that the historical
interface currently renders correctly. DXMT absence alone also cannot explain
the difference: the historical Portside baseline disabled DXMT too.

## Signature and diagnostic limits

The stock launcher and SDK passed their component signature checks. The stock
template does not pass strict whole-bundle verification. A separate preliminary
signing control sealed only disposable assembly files with a local Developer ID,
preserved existing security flags/entitlements, and pointed CFBundleExecutable
to the same real launcher instead of its symlink. Nested template/renderer
resources also needed signatures. Verification passed before prefix setup but
failed after the external-prefix link was created (`invalid destination for
symbolic link in bundle`). This control did not establish a distributable wrapper.

The subsequent stock control used the original archive bytes, the historical
artifact validation and additional checks of the launcher/SDK actually executed.
It did not claim a valid sealed mutable wrapper. Gatekeeper/quarantine settings
were not changed, and no signature-ignore, sandbox-disable or library-validation
exception was added. A distribution design must address this packaging boundary
separately; the diagnostic control is not a signing/notarization acceptance test.

Screen capture remained unavailable. No screenshot was captured or inspected;
window titles and process metadata are not rendered-content evidence. A Windows
window-text probe run outside the launcher failed (SIGFPE initially, then timed
out with baseline synchronization flags); a secondary launcher probe did not
produce usable text. These inconclusive probes are not graphical-cause evidence.

The current investigation commit remains on main. The historical worktree and
disposable evidence remain local. This report is a later, uncommitted test result;
no second commit, release, dispatch, deployment or publication was performed.
Restoring this engine unchanged is not an accepted fix under the retained sandbox
constraint. The Sikarugir integration needs an engine without that injected
workaround and a new graphical control before it can be accepted.
