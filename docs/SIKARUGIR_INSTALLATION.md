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
