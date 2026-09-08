# Original Sikarugir baseline retest — 2026-09-08

**Verified: rendered Steam login and interaction in the disposable fixture.**
The project owner withdrew the restrictions previously cited as preventing use
of the original Sikarugir engine. The historical test was resumed with the
unmodified Template 1.0.11 and WS12WineSikarugir10.0_6. Those earlier restrictions
are not grounds to refuse this authorized baseline test. The earlier historical
and renderer-overlay reports retain their original, narrower scope.

## Verified inputs and scope

The existing synthetic fixture came from unchanged historical Portside source
at `8e9eda9e19c0fee06a20b4e8b2ce2781cb62dab6`. Its original installer had created
the wrapper, external prefix and Valve Steam installation. See the
[historical report](SIKARUGIR_LEGACY_VALIDATION.md) for artifact provenance,
full archive hashes, installation steps and the 25-test historical desktop build.
No everyday prefix, native Steam, installed runtime, account, game or library
was imported or changed.

Before launching again:

- Both original kernelbase DLL hashes still matched the verified engine archive.
- Strict checks of the executed Sikarugir launcher and SDK components passed.
- The prefix resolved inside the fixture's private home; its synthetic marker
  was hashed and retained.
- No process held that fixture's Steam or webhelper executable.
- Log offsets and the Steam executable hash were recorded before LaunchServices
  opened the exact wrapper with private HOME/CFFIXED_USER_HOME/TMPDIR values.

This retest did not change the original engine, add Portside program flags,
change renderer toggles or alter macOS security settings. The engine's original
compatibility behavior was allowed to run under the updated user instruction.

## Observed graphical result

The updated Valve Steam client remained `1788652215`, matching the black-window
controls with Portside Wine 11.17. The Steam executable hash did not change during
this retest. It was not necessary to restore an older Steam client.

CoreGraphics and Accessibility identified the fixture-owned 700 by 440 login
window. Screen-recording and Accessibility permissions were available.
`/usr/sbin/screencapture -x -o -l <owned-window-id> <fixture-image>` captured only
that window. The image was actually opened and visually inspected: Steam's logo,
account/password fields, sign-in controls and the login panel were rendered.

An initial targeted mouse event did not establish the intended checkbox change.
With the account field focused, keyboard events `Tab`, `Tab`, `Space` were then
sent only to the positively identified fixture PID using `CGEvent.postToPid`.
The next owned-window capture visibly showed **Remember me changed from checked
to unchecked**, with keyboard focus around that checkbox. This establishes actual
rendered UI interaction, beyond PID, title, Dock or readiness detection. No account
name/password was entered, no login was submitted and no account was used.

The window captures and fixed-result JSON remain only in the disposable evidence
directory, outside Git and product bundles. Login-session images are not published.

| Comparable control, updated Steam `1788652215` | Result |
| --- | --- |
| Sikarugir launcher + Portside Wine 11.17, tested renderer variants | Black window, including user confirmation |
| Original Sikarugir launcher + WS12WineSikarugir10.0_6 | Login content rendered; checkbox interaction visibly confirmed |

Current process inspection confirmed the old engine still injects
`--no-sandbox --in-process-gpu --disable-gpu`; the new GPU log reports acceleration
disabled by command line. This is an observed property of the now-authorized
baseline. The comparison establishes that the original composition works for
this login test; it does not isolate which individual engine change or switch
is necessary. No modified binary was used to attempt that attribution.

## Preservation, checks and limits

After recording the successful interaction, cleanup checked the native launcher's
executable before terminating that PID and invoked only this fixture's wineserver
with its exact WINEPREFIX. No process-name-wide termination was used. Final
checks found no fixture Steam/helper executable holders, and the preservation
marker remained byte-identical.

Commands/checks in this retest included `git status`, SHA-256 checks,
`codesign --verify --strict` on launcher/SDK, the existing isolated LaunchServices
harness, owned-file `lsof` checks, Swift CoreGraphics/Accessibility probes,
window-only `screencapture`, targeted keyboard input, and scoped wineserver
shutdown. Documentation links and `git diff --check` passed. No implementation
changed in this retest, so the previously recorded Swift/script/build checks were
not rerun as though they constituted new graphical evidence.

**Scope of success:** the original historical integration renders the current
Steam login and responds to input on this Mac. Account authentication, library
views and games were not tested. Wine remains x86_64 via Rosetta.

**Product state:** the current main-branch runtime builder still produces the
independent Portside/Wine wrapper. This retest establishes a working reference;
it does not silently migrate or replace the installed product. The prior
whole-wrapper signing/external-prefix seal issue remains separate from the
verified launcher/SDK component checks. A restored distributable integration
still needs its implementation and authenticated app/runtime packaging verified.
No new commit, push, workflow dispatch, deployment or publication occurred.
