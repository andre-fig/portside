# Sikarugir integration — 2026-09-08

**Migration started after checkpoint `cb02472b`:** the native host now has an
explicit Sikarugir integration mode, and a local builder assembles its candidate
from the approved original input set. See [SIKARUGIR_ADAPTER](SIKARUGIR_ADAPTER.md)
for current implementation, controls and remaining product/release integration.

The latest [authorized original-engine retest](SIKARUGIR_RESTORE_VALIDATION.md)
now establishes rendered login and actual checkbox interaction with the original
Sikarugir launcher and WS12WineSikarugir10.0_6, using the same updated Steam
client as the black-window controls. The project owner withdrew the restrictions
previously cited against that baseline. Earlier source-only and workaround
blocker statements below describe the preceding decision scope; they must not
be used to refuse this authorized reference. Main's product migration and full
bundle/release validation are still pending.

The [launcher/overlay continuation](SIKARUGIR_OVERLAY_VALIDATION.md) now verifies
x64/x86 execution through the original Sikarugir launcher with Portside's engine,
and visually reproduces the black Steam window. It identifies missing
`WINEDLLPATH_PREPEND` support, now corrected in a locally rebuilt source engine.
The reference DXMT then creates FL 11_1 devices but rejects Steam's cross-process
presentation; a safe software control also remains black, confirmed by the user.
It does not establish source-built Launcher/SDK availability or graphical success.

The later user-authorized [historical runtime test](SIKARUGIR_LEGACY_VALIDATION.md)
executed the old integration in a disposable environment and identified automatic
sandbox-disabling flags in its engine. Its results supersede the earlier
inspection-only scope below; no graphical acceptance has been established.

**Target adopted; runtime migration blocked.** Portside automates Sikarugir
installation, configuration, updates and Steam launch. Reusing its Wine fork
inside an independent wrapper does not fulfill the project owner's clarified
requirement. D15 in [DECISIONS](DECISIONS.md) supersedes the independent-wrapper
choice, retaining source-build, provenance, signing and preservation requirements.

## Verified implementation gap

[build-wrapper.sh](../scripts/build-runtime/build-wrapper.sh) compiles Portside's
Swift host and copies its template. The host directly executes Wine; neither
Sikarugir Launcher nor SikarugirSdk participates. Runtime assembly supplies Wine,
winetricks and FreeType, advertises WineD3D and disables other renderer flags.

The public Wrapper tree at `f3bdf2b4939700754d77744e7b91a8eff313770d` contains
only `README.md` and `NewestVersion.txt`, which names `Template-1.0.15`.
Engines contains a list and site metadata, not a complete engine recipe.
The FOSS repository supplies Configure sources, not Launcher/SDK sources.
The public organization inventory and current trees were rechecked on this date.
GitHub's generated source ZIP does not prove that separately uploaded binaries
can be built from that tree.
[Wrapper source](https://github.com/Sikarugir-App/Wrapper/tree/f3bdf2b4939700754d77744e7b91a8eff313770d),
[FOSS source](https://github.com/Sikarugir-App/Sikarugir-foss-sources/tree/4be1b048f8df14b073a6e39e8245bbb52c6a71c0).

## Inspected reference

The official `Template-1.0.15.tar.xz` was downloaded into a disposable reference
directory, checked against GitHub asset size/SHA-256, and read without extraction,
installation or execution. It is **not a production build input**.

- Size: 87,477,092 bytes.
- SHA-256: `34273bcce885ce5a7fd6937af9ea344bb9961de7d55d6193f7413142e835c8c3`.
- Asset update: `2026-09-04T03:37:26Z`.
- Pin: [sikarugir-reference.json](../upstream/sikarugir-reference.json).

| Area | Inspected official template | Current Portside |
| --- | --- | --- |
| Launcher | `launcher` links to `Sikarugir`; `wineskinlauncher` links to `launcher`; SikarugirSdk present | Independent Swift host directly starts Wine |
| Direct3D 10/11 | DXMT `v0.80-213-g4ddb20e`, x86/x64 DLLs and `winemetal.so` | WineD3D; tested maximum feature level 9_3 |
| Direct3D 9 | D9VK `DXVK-Sikarugir-async-v1.10.3`, `D9VK=1` | WineD3D |
| Vulkan | MoltenVK and KosmicKrisp libraries/ICD descriptions | Tested builtin loader reports no compiled Vulkan support |
| Other payloads | GStreamer framework, alternative renderers | Not supplied by current assembly |
| Advertised macOS floor | `LSMinimumSystemVersion=14.0` | App/wrapper/build target 13.0 |
| Optional addons | `Skip Mono=0`, `Skip Gecko=0` | Temporary deferral during `wineboot -u -r` |

These are inventory/configuration facts, not proof of launcher selection logic,
device capabilities or the backend actually selected by Steam. The DXMT version
matches the prefix of public commit `4ddb20e54672c0cb56115ce80d6db1beef94ae28`;
it is not a complete source-build receipt for the template.

[Upstream release notes](https://github.com/Sikarugir-App/Wrapper/releases/tag/v1.0)
describe a CEF black-screen fix in Template 1.0.13 for systems **below macOS 26**
and subsequent KosmicKrisp updates. This is relevant wrapper-level evidence,
not proof of a fix on the tested macOS 26.6.2.

The [inspector](../scripts/build-runtime/inspect-sikarugir-template.py) verifies
the pin and selected archive members without extracting them:

```sh
python3 scripts/build-runtime/inspect-sikarugir-template.py "$SIKARUGIR_REFERENCE_ARCHIVE"
python3 -B -m unittest discover -s scripts/tests -p test_inspect_sikarugir_template.py -v
```

It reports `sourceBuildVerified=false` and graphical acceptance `not tested`.
No builder, fetcher, manifest generator or publisher consumes the reference pin.
No compiled reference enters vendor, Portside bundles, user prefixes or storage.

## Blocker and remaining implementation

**Blocked:** matching Sikarugir Launcher/SDK sources, build recipe and complete
dependency/engine configuration are missing. The retained
[authorization statement](../SIKARUGIR_AUTHORIZATION.md) does not supply those
files. Source access was requested from the project owner; no message was sent
to the upstream author.

After obtaining the inputs:

1. Import through controlled synchronization with commits, dependency checksums,
   notices and provenance. Match the engine to its actual recipe; Wine master
   alone does not establish a packaged engine's source identity.
2. Build locally and adapt the host to the real Sikarugir entry point/lifecycle,
   retaining structured arguments, containment, receipts and process ownership.
   Do not guess SDK APIs or renderer toggles from filenames.
3. Map prefix preparation into the external-prefix contract; test new, existing
   and interrupted preparation with synthetic preservation/startup markers.
   Existing-prefix Mono deferral and honest readiness remain required behavior.
4. Resolve macOS floor, Rosetta and Windows x86/x64 support across app, wrapper,
   engine and manifest. Do not revert to the defective ARM64 loader, hide Intel
   notices or import upstream security settings contrary to task constraints.
5. Compare integrated source builds in isolated fixtures with matching Steam
   versions/hashes, backend/capability probes and actual pixels/interaction,
   including update/relaunch. Never copy credentials or everyday prefixes.
6. Produce a new authenticated runtime and signed/notarized app through the
   existing same-commit CI chain only when publication is authorized. Preserve
   event-driven prerequisites without inter-workflow polling.

Adding DXMT to the independent host alone still leaves the integration incomplete.
A precompiled commercial fallback violates the retained source-build constraint.
Neither was substituted for the missing sources.

## Validation and graphical result

Synthetic inspector tests cover changed size/checksum, missing payloads,
duplicate/traversing paths, symlink components and archive links, and verify
that inspection neither extracts files nor claims build/graphical acceptance.
The actual pinned template passed inspection.

The [preceding candidate](STEAM_GRAPHICS_FIX.md) failed visible acceptance:
the user confirmed Steam remained black. SwiftShader readback demonstrated only
offscreen rendering. No screenshot was captured/viewed because screen capture
was unavailable. A later fixture-only `-cef-disable-gpu` control removed the
logged runtime GPU-disable/reload transition, but has no visual or interaction
acceptance and was not added to product defaults.

App/runtime behavior remains the earlier local candidate. These changes correct
architectural instructions and add reproducible reference inspection; they do
not complete the runtime migration or repair the black window. No Sikarugir
execution or before/after graphical success is claimed.
