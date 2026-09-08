# Sikarugir runtime adapter — 2026-09-08

**Implementation started after user-authorized checkpoint `cb02472b`.** The
checkpoint preserves the renderer investigation and the successful original
Sikarugir login/interaction test. No push occurred. Subsequent adapter work is
uncommitted and uses only disposable fixtures.

## Adopted input and integration contract

The owner approved restoring the original Sikarugir composition. D19 in
[DECISIONS](DECISIONS.md) supersedes the source-only blocker for this exact set.
[upstream/sikarugir-runtime.json](../upstream/sikarugir-runtime.json) pins the
Template 1.0.11, WS12WineSikarugir10.0_6 and original winetricks by size/SHA-256,
retaining upstream URLs, producer, license records and the absence of a verified
matching binary build recipe. Portside assembles these components; it does not
claim to have compiled the upstream binaries.

The native host accepts explicit `integration: sikarugir` in its authenticated
wrapper configuration. Missing integration retains the existing direct-Wine
protocol; an unknown value fails decoding. A missing/nonexecutable launcher or
SDK, or either resolving outside the wrapper, fails without a Wine fallback.

| Request | Sikarugir integration behavior |
| --- | --- |
| Normal Steam opening | LaunchServices opens the original bundle entry point (`launcher` resolving to `Sikarugir`), with the stock SDK and configured Steam program |
| `--winetricks -q steam` | Original launcher with `WSS-winetricks steam`; quiet setup is configured by the template |
| `--create-prefix` | Original engine's native `wine wineboot.exe -u -r`, with Mono/Gecko deferral only for that process |
| Version and diagnostic Windows programs | Original engine through the existing bounded host command/receipt contract |

The desktop resolves the original application launcher separately from the
contained `PortsideRuntimeHost` maintenance helper. Unknown integrations,
invalid configurations and missing/escaping components fail validation. The
desktop sends no Portside UUID arguments to Sikarugir, even if an old receipt
capability marker is present. The helper rejects normal Steam launches in this
mode; it does not act as a subprocess proxy for the original native app.

UUID termination receipts remain available for helper commands and legacy
direct-Wine launches. Sikarugir Steam opening uses native application lifetime
and the existing owned-process/window/manual confirmation checks; a host receipt
is not promised for it. The host retains argument arrays, bundle identity/containment,
sanitation and output limits. It supplies the
contained template Frameworks directory for this engine's native dependencies.
The original engine has no `bin/wineboot` shim, so preparation invokes its
builtin `wineboot.exe` through the native executable. It does not repeat expensive
preparation on every Steam opening or apply the Wine 11-specific CEF Vulkan
registry policy to this composition.

A real first-prefix control exposed delayed registry persistence: Wine returned
0 before its new registry files appeared. The host now waits up to 15 seconds
for nonempty regular `system.reg`, `user.reg` and `userdef.reg` before reporting
Sikarugir prefix preparation complete. It does not kill processes to force that
state. A regression test reproduces registry writes after Wineboot exits.

## Local assembly

[build-sikarugir-candidate.py](../scripts/build-runtime/build-sikarugir-candidate.py)
requires the three already-downloaded exact inputs and a locally built host.
It performs size/hash validation, safe extraction and original launcher/SDK
component signature checks, preserves their bytes and notices, adds the host and
writes the selected integration/configuration. It records exact original inputs,
launcher/SDK/host hashes and host source hash with `distributionReady: false`.

Output must be a new directory inside the checkout's `build` directory. Existing
or external destinations, malformed input sets, altered/symlinked inputs,
archive escapes, duplicate archive members and signature failures are rejected.
Contained archive hardlinks remain supported; their extraction does not count
as a duplicate member. Assembly does not create or migrate any prefix, download
inputs or publish artifacts. Execution fixtures create their own external prefix.

```sh
swift test --package-path apps/runtime-host
swift build --package-path apps/runtime-host
python3.14 scripts/build-runtime/build-sikarugir-candidate.py \
  --inputs "$SIKARUGIR_VERIFIED_INPUT_DIRECTORY" \
  --host "$PWD/apps/runtime-host/.build/debug/PortsideRuntimeHost" \
  --output "$PWD/build/sikarugir-integration-candidate"
```

The destination must be unused. Python 3.12+ with `tarfile.data_filter`, macOS
`codesign`, and the matching local Swift host are required. The approved inputs
remain outside Git and installed runtime directories.

## Native controls and current completion

The corrected candidate created a disposable prefix in 18.803 seconds and
returned only after the registry files existed. Existing-prefix update returned
0 in 4.686 seconds, retained its synthetic preservation marker and did not run
the synthetic Run entry. That entry was then removed from the fixture. Subsequent
Windows x64/x86 commands returned the expected 37/23. Optional-addon skipping
was not persisted in the template or registry.

Official Steam installation through the helper and original `WSS-winetricks`
returned 0 in 66.937 seconds. Steam then updated its Win32 bootstrap to Win64
client 1788652215. The actual desktop core accepted the final candidate layout
and opened its original entry point with no Portside launch arguments. A further
existing-prefix preparation through the final helper completed in 13.892 seconds.

**Graphical result: Unknown.** The updater exposed an owned window, but a capture
raced its replacement and yielded no usable image. Subsequent observations did
not detect a final visible login window. This happened with the initial helper
proxy prototype and with the final original entry point. A comparison against
the previously working synthetic prefix, followed by a replay of the original
wrapper itself, also produced no visible login window in this later session.
This does not isolate the entry point, prefix preparation or Steam update as
the cause. No new black-window screenshot or rendered interaction was obtained.
The earlier [original-runtime control](SIKARUGIR_RESTORE_VALIDATION.md) proved
login rendering and interaction at that time; it does not validate this adapter.
Both synthetic preservation markers remained unchanged. Only the fixtures'
own processes were stopped, and their Steam/helper file ownership checks were
empty afterward. The candidate's external link was restored to its own prefix.

**Verified automated checks:** 23 host tests and build; 152 desktop tests (one
optional signed-app network probe skipped) and build; 87 script tests; production
policy, source audit, Wine/winetricks snapshot validation, workflow lint and
diff whitespace. Tests cover original entry-point/helper separation, UUID
exclusion, rejected unknown/escaping components, prefix data preservation,
delayed registry writes, child-only addon deferral, exact input verification,
safe archive extraction and component-signature failure.

**Remaining product work:** connect the approved assembly to the desktop
installer's component layout, validated engine transfer, runtime provenance/SBOM,
full bundle signing and authenticated same-commit app/runtime release. Current
commercial workflows and installed runtimes are not switched by this development
entry point. Component signature checks do not establish full-wrapper signing
acceptance; the external-prefix seal boundary remains to be handled. Account
login, library views and games need separate acceptance. Rosetta remains required.
