# Sikarugir installation integration — 2026-09-08

**Verified local installer and rendered-login interaction; customer release validation pending.** Checkpoint `d4cccd72` preserves the
first adapter. Subsequent changes connect the approved composition to Portside's
three-archive installer and runtime workflow. They have not been published or
installed into the everyday environment. This continuation supersedes the
adapter document's statements that installer and workflow integration are absent.

## Preparation belongs to Portside

Portside must perform installation and configuration in the background. Users
must not operate Sikarugir Creator, Configure, or another project's setup wizard.
Only the configured Steam application is opened through LaunchServices.

The runtime helper prepares new and existing external prefixes with the original
engine's `wineboot.exe -u -r`. Mono/Gecko deferral belongs only to that subprocess;
no application-wide override is persisted. Preparation runs during installation
or runtime replacement, not on each Steam opening. The original launcher receives
`WSS-winetricks steam` for official Steam installation, with `Winetricks silent=1`.
The host rejects interactive setup configuration and unsupported verbs before
starting the original launcher. No Creator/Configure invocation is part of setup.

Before normal opening, the desktop requires an external prefix link, complete
registry files, the configured Steam path, and a nonempty contained Steam
executable. Incomplete setup produces a Portside error instead of handing the
wrapper to an upstream interactive fallback. This also rejects the experimental
empty internal prefix plus environment-only override used during local testing.
That experiment was stopped after the user reported an upstream installer UI;
the exact dialog's ownership was not captured, so its origin remains unproven.

## Archive and installer contract

`upstream/runtime-integration.json` selects `sikarugir` and
`upstream/sikarugir-runtime.json` pins Template 1.0.11,
WS12WineSikarugir10.0_6 and the original winetricks input. The package builder
compiles only PortsideRuntimeHost, preserves original engine archive bytes, and
assembles the wrapper and winetricks archives with accurate upstream provenance.
There is no Wine compilation or unverified download fallback.

The desktop rechecks all three archive sizes and hashes before replacement.
It installs the engine under `Contents/SharedSupport/wine` and winetricks as the
original executable file. The wrapper contains the fixed relative prefix link
`../../../../Prefixes/PortsideBaseline`. The installer validates it against its
managed root and preserves wrapper metadata. Existing prefix contents are kept;
a legacy embedded prefix containing data is rejected rather than deleted.
The injected installer root permits the real production installer to run in a
fresh disposable home, without redirecting the user's actual state directory.
Pending-manifest fresh cryptographic revalidation remains a separate known gap.

## Signing and release boundaries

Linux verifies and transfers the exact approved upstream inputs with a receipt
bound to the checkout and workflow attempt. macOS compiles the small helper,
assembles archives, and runs native new/existing-prefix and Windows x64/x86
controls. Original Sikarugir source changes select assembly, not hosted Wine
compilation. Publication requires the same archive hashes, source/run evidence,
producer/SBOM records, native results and component signatures. Existing automatic
application release still requires successful CI and runtime from the same commit;
there is no workflow polling or additional publication trigger.

The Portside host and original native launcher receive Developer ID signatures;
the original SDK, Wine and wineserver retain their signatures. All five components
are checked individually with strict verification and recorded hashes. Local
ad-hoc candidates cannot satisfy the distribution signing gate. The runtime job
uses the existing signing secrets through an ephemeral keychain with cleanup.

This is **not a fully sealed or notarized standalone wrapper application**.
A local whole-wrapper signing experiment failed strict validation because the
external mutable prefix is an invalid sealed-bundle symlink destination. The
experiment's layout relocations were discarded. No relaxed resource rules or
Gatekeeper/quarantine changes were added. Runtime archives retain their manifest
trust chain; the main desktop application's signing/notarization pipeline remains
separate. A signed release and installed customer launch still require validation.

## Local evidence and limits

The actual desktop installer completed a fresh installation in 40.716 seconds
and replacement over an existing prefix in 34.033 seconds. The synthetic marker,
wrapper metadata and skipped Run entry were verified. Windows x64/x86 controls
returned 37/23, and official quiet Steam installation completed successfully.
All five native component signatures verified; this initial candidate was ad-hoc
and correctly did not qualify for distribution.

Earlier UUID-length fixture paths failed prefix preparation with status 53 and
missing kernel32; shorter fixture names succeeded. Copying original archive bytes
instead of normalizing timestamps did not independently resolve that failure.
The relationship to path length remains a hypothesis, not a proved root cause.

The final Developer ID candidate completed new/existing preparation in
39.470/34.948 seconds and official silent Steam installation. Captures verified
both Steam update stages and then the complete login form after updating to
client 1788652215. The login appeared approximately 50 seconds after the updated
client started. Targeted Tab/Tab/Space changed Remember me from checked to
unchecked; before/after images were inspected. No credentials were entered.
The graphical archive binding is wrapper SHA-256
`f2f55ca7115b352ff627a50f396d602a35a6a41c1de0d73b4992f85ea1ee49a1`,
with the unchanged pinned engine and packaged winetricks. The synthetic marker
survived; only fixture-owned processes were stopped afterwards.

This verifies the integrated original composition locally, including after the
Steam update. It does not isolate which single upstream component accounts for
the difference from the black Wine 11 controls. Setup observations detected no
owned Configure/Creator window, but were point-in-time observations rather than
continuous capture. The earlier user-reported dialog remains unidentified.

A separate final archive build corrected an inline `codesign -R` requirement
syntax error in the validation script: inline requirements need the `=` prefix.
The prior binaries already had Developer ID signatures, confirmed by the corrected
command; they had been incorrectly classified as local candidates. Repackaging
and real native installation then passed all five signature checks and both
Developer ID requirements. New/existing installation took 40.576/35.121 seconds.
That final report is bound to wrapper
`78635dfea3d000bdf74c438cdbef161eeb33eca0ac7c9997e5342b90afde2182`;
it does not claim a second graphical run against those newly signed bytes.
Only the attestation command changed; the runtime source and composition did not.
The original engine still depends on Rosetta and includes the upstream Steam
command policy documented in the authorized restore report. Intel deprecation
is a future compatibility limit, not proof of the black-window cause.

Run local packaging only with an unused output directory and exact verified inputs:

```sh
python3.14 -B scripts/build-runtime/package-sikarugir-runtime.py \
  --inputs "$SIKARUGIR_VERIFIED_INPUT_DIRECTORY" \
  --output "$PWD/build/sikarugir-runtime-validation" \
  --version 0.1.36 \
  --download-prefix "$PORTSIDE_ARTIFACT_DOWNLOAD_PREFIX"
python3.14 -B scripts/build-runtime/validate-sikarugir-installation.py \
  build/sikarugir-runtime-validation --install-steam --keep-fixture
```

Set `PORTSIDE_CODESIGN_IDENTITY` to an available Developer ID identity for
component distribution-signature checks. The default is local ad-hoc. Signing
requests Apple's timestamp service; these commands do not publish anything.
The optional Steam flag downloads only Valve's official installer and fixture
prerequisites. Cleanup uses the fixture's exact engine and prefix. Graphical
acceptance requires a separate owned-window capture and actual interaction.

## Live upgrade metadata cache correction

The live 0.1.35-to-0.1.36 upgrade exposed a missed transition: Foundation cached
the old runtime's `CFBundleExecutable` at the persistent wrapper URL. Installation
replaced the bundle correctly, but the still-running desktop combined the old
entry point with the new integration configuration and rejected it. Recovery
restored the legacy wrapper before Steam was opened.

Runtime resolution now reads current on-disk plist bytes through Foundation,
retaining bundle identifier and executable containment/existence checks. It does
not flush global caches, restart unrelated processes or modify installed binaries.
The native probe holds synthetic legacy Bundle metadata across real installation,
in addition to new/existing-prefix checks. Publication requires the corresponding
`legacyMetadataReplacementVerified` result. Unit controls reproduce the original
failure and cover rollback plus invalid metadata replacement. A corrected desktop
release is required for a live migration; the existing 0.1.36 app lacks this fix.

## Automatic opening and LaunchServices refresh — 2026-09-09

After app/runtime/Steam checks, an existing installation now opens Steam
automatically when no managed Steam session is running, including after a
runtime replacement. Fresh setup retains its automatic launch. An existing
session is preserved. The subsequent automatic-closure policy removes customer
confirmation after launch; manual graphical acceptance remains a separate test.

Live 0.1.41 logs recorded successful runtime installation at 23:13:54 UTC,
then a maintenance-host argument rejection at 23:14:07 and no detected Steam
process at 23:14:08. The installed plist selected `launcher` with Sikarugir
integration. This is consistent with stale LaunchServices registration selecting
the previous host; the logs do not independently prove the cache contents.

Before NSWorkspace opens the validated wrapper URL, the desktop now forces
`LSRegisterURL` to refresh that wrapper's registration even when replacement
preserves timestamps. Registration failure stops opening with an explicit error.
Preparation checks and the separation of Sikarugir and legacy receipt arguments
remain mandatory. No global cache reset or installed-bundle edits are used.
The regression fixture holds old Bundle metadata across replacement and checks
forced registration, argument selection, registration errors, and rejection of
incomplete Steam preparation before registration. It does not launch real Steam.

## Startup privacy restrictions — 2026-09-10 UTC

**Implemented but not end-to-end validated:** newly assembled wrappers configure
Steam with `-preventsteamdiscovery`. This option is present next to the remote
client broadcast/listener implementation in the inspected Valve Steam client.
It targets Steam device discovery; it is not a network firewall or proof that
no game, LAN transfer, or other Steam feature can request local-network access.
The desktop accepts the exact new flag and the empty legacy flag for upgrades
and rollback, rejecting other program flags. Signed installed metadata is not
rewritten. New privacy defaults require a newly packaged runtime.

The user reported microphone permission during Steam startup, without using
voice chat. Local TCC logs attributed the microphone request to Wine under the
Sikarugir launcher. That installed launcher lacked Hardened Runtime. New runtime
packaging enables Hardened Runtime on the launcher without audio-input or other
resource-access entitlements. The only exception is library validation, because
the pinned original SDK retains its upstream signature. Existing component
signature checks remain; the SDK and engine bytes/signatures are preserved.
Packaging and native installation validation inspect the actual launcher code
flags and exact entitlements and reject missing hardening or extra permissions.

Apple documents microphone access under the
[audio-input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input)
and explains that
[local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
is triggered by network operations. Removing usage-description strings is not an
access-denial policy. These changes do not modify macOS privacy decisions or
reset permissions. Voice input and automatic remote-device discovery are outside
the new startup defaults; playback, internet access and the original Wine engine
are retained. Real startup without prompts, audio playback, and games still need
graphical acceptance with the packaged runtime.

## Automatic desktop closure — 2026-09-10 UTC

The customer flow no longer asks whether the Steam window is blank or usable.
Fresh setup and subsequent launch close Portside automatically after managed
Steam/window/webhelper detection and the final process/renderer check. Helpers
start before closure, and Steam remains independent. Diagnostic readiness stays
unverified; this product transition does not assert rendered interaction.
Detected startup failures still show the retry screen.
