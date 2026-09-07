# Steam first-launch failure in 0.1.28

Investigation: 2026-09-06 local / 2026-09-07 UTC, on Apple silicon,
macOS 26.6.2 (25G83). Starting commit:
`13305142e8a3c761bd4330b4d5303ddd9c8cf80b`, clean `main` worktree.
Installed application 0.1.28; runtime configuration 0.1.26; Wine 11.17.
All changes are local source changes. No commit, push, publication, release,
manifest update, notarization submission or deployment was performed.

## Proven cause of the immediate status 9

**Verified:** the failing child is killed by **SIGKILL**, not `exit(9)`.
Using the installed engine with a newly allocated prefix, `wine --version`
returned 0 in 22 ms, while `wine cmd /c exit 0` returned Python status `-9`
in 7 ms with no output. Separate probes with a direct prefix path and a symlink
both received SIGKILL (25 ms and 11 ms respectively). The everyday prefix was
not executed, recreated, inspected for account contents, or modified.

The macOS kernel recorded a security-policy refusal for the probe PID at
`engine/lib/wine/aarch64-unix/wine`. That is a different Mach-O from `bin/wine`.
Inspection showed:

| Binary | Architecture | `__PAGEZERO` | `__TEXT` address | Static codesign |
| --- | --- | --- | --- | --- |
| `engine/bin/wine` | arm64 | 4 GiB | `0x100000000` | Valid, linker ad hoc |
| `engine/lib/wine/aarch64-unix/wine` | arm64 | 4 KiB | `0x1000` | Valid, linker ad hoc |
| `engine/lib/wine/aarch64-unix/ntdll.so` | arm64 | Library | Library | Valid, linker ad hoc |

The source explains the divergence. `vendor/wine/configure.ac` supplies Darwin
loader flags `-segalign,0x1000,-pagezero_size,0x1000`. In
`vendor/wine/dlls/ntdll/unix/loader.c`, `check_command_line()` handles
`--version` before `reexec_loader()`. A successful version probe therefore
does not establish that macOS can execute the actual Windows loader.

To isolate the cause from Wine, Steam, credentials, prefixes and AMFI log wording,
[test-loader-layout.py](../scripts/build-runtime/test-loader-layout.py) compiles
`int main(void) { return 0; }` with standard and Wine-style layouts for each
architecture. This session ran both ad hoc and Developer ID comparisons:

| Architecture/layout | Ad hoc: verify / execute | Developer ID: verify / execute |
| --- | --- | --- |
| arm64, standard layout | 0 / exit 0 | 0 / exit 0 |
| arm64, Wine loader layout | 0 / SIGKILL 9 | 0 / SIGKILL 9 |
| x86_64, standard layout | 0 / exit 0 | 0 / exit 0 |
| x86_64, Wine loader layout | 0 / exit 0 | 0 / exit 0 |

**Conclusion:** the recipe selected the host's arm64 architecture for a Darwin
loader layout that cannot run as arm64 on this macOS. Valid Developer ID signing
does not make that layout executable. Native arm64 Wine also requires a suitable
Windows x86 CPU-emulation backend; emitting i386/x86_64 PE files alone does not
supply one. The correction uses the x86_64 Wine/WoW64 path through Rosetta,
already required by Portside. This is consistent with the Wine maintainers'
[Apple silicon build discussion](https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/thread/Z5H2PERCSGNITZNGBPJISF4L3BGXGQAR/).
The local controlled experiment, rather than that historical discussion or AMFI
wording alone, establishes this incident's architecture/layout failure.

## Signature findings and scope

**Verified, scoped:** an inspection of all 35 non-symlink Mach-O files in the
installed wrapper found 35 ad hoc signatures, with 34 passing strict static
verification. The host failed with “code has no resources but signature
indicates they must be present.” All inspected Wine code, including the nested
loader and `ntdll.so`, passed. The host executed the probe successfully; this
resource-seal defect is distinct from the child's reproducible SIGKILL.

No Gatekeeper setting, quarantine attribute, provenance attribute, security
validation or installed binary was changed. Only freshly compiled disposable
control programs were signed for the Developer ID comparison. Runtime-wide
Developer ID signing/notarization is still not implemented by the current
wrapper/engine assembly scripts; signing the desktop app does not sign the
downloaded runtime. Final distribution validation remains necessary. Apple's
[distribution signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
explains signing nested code individually and verifying the final product.

## Source changes

- The Wine recipe now requires x86_64; native build tools remain native. Engine
  storage identity includes architecture and recipe/dependency hash, preventing
  reuse of the earlier arm64 artifact for the same Wine source commit.
- Pinned FreeType source is downloaded over HTTPS, verified against the existing
  dependency SHA-256, compiled for x86_64 and included with its notices and SBOM
  entry. This avoids linking the target Wine build to an arm64 Homebrew library.
- Engine packaging and extracted-layout validation execute both x64 and x86
  Windows `cmd` programs in a new prefix linked through a symlink. Nonzero
  expected Windows exits prove execution; version output alone cannot pass.
- The host logs sanitized executable/argument summaries, execution error codes,
  termination status, `exit`/`uncaughtSignal`, signal and monotonic duration.
  It bounds captured output and writes a UUID-scoped terminal receipt before
  a two-second deadline for detached output. Dispatch events replace polling;
  an inherited `SO_NOSIGPIPE` socket prevents closing capture from signalling
  descendants. Late writes receive `EPIPE`. Receipt retention keeps 100 historical
  files for seven days, protecting the current launch and the last five minutes.
- The desktop negotiates receipt support through wrapper configuration. Older
  hosts receive no new arguments. It checks LaunchServices lifetime, owned
  descendants and the canonical prefix; unrelated new Wine processes cannot
  hide a failure. One second of no managed runtime children after termination
  ends readiness early. A living child retains the graphical deadline.

| Evidence | New error code | User-facing meaning |
| --- | --- | --- |
| Wine cannot be executed | `wine_execution_failed` | Wine could not execute; Steam was not started |
| Wine receives a signal | `wine_terminated_by_signal` | Includes the signal number |
| Wine exits nonzero with no surviving runtime child | `wine_exit_failed` | Includes the actual exit status |
| Steam never appears | `steam_process_not_started` | Steam did not start |
| Observed Steam disappears before readiness | `steam_exited_before_ready` | Steam closed before readiness |
| Steam remains running without a window | `steam_window_failed` | The separate process-without-window failure |
| A current window lacks webhelper | `steam_webhelper_failed` | Window detected, web helper absent |
| LaunchServices cannot start the wrapper | `runtime_launch_failed` | Runtime could not start |

The previous code discarded the launch handle, waited the full graphical
deadline and used `steam_window_failed` with a claim that Steam started even
when `processStarted=false`. Both initial setup and subsequent opening now use
the same failure classification. Current window plus webhelper remains
`visibleButUnverified`, never automatic proof of usable Steam UI.

## Validation evidence

Sanitized generated evidence is under ignored `build/first-launch-evidence/`.
It is local evidence, not a published runtime. Reproducible source commands:

```sh
swift test --package-path apps/runtime-host
swift build --package-path apps/runtime-host
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/build-runtime/test-loader-layout.py
./scripts/build-runtime/source-audit.sh
./scripts/upstream/validate_snapshot.sh vendor/wine
./scripts/upstream/validate_snapshot.sh vendor/winetricks
python3 -B -m unittest discover -s scripts/tests -v
actionlint .github/workflows/*.yml
./scripts/validate-production-policy.sh
git diff --check
```

Final results after production-blocker review: **15 host tests passed; 132 desktop tests completed with one
explicitly unconfigured signed-app probe skipped and no failures. Both Swift
builds passed.** Source audit, Wine/winetricks snapshot checks, shell/Python/JSON
syntax, metadata/SBOM JSON generators, production policy, local documentation
links and diff whitespace checks passed. Existing Sparkle test deprecation
warnings remain unrelated to this change.

Set `PORTSIDE_CODESIGN_IDENTITY` from the approved external environment to add
the Developer ID layout comparison. No private value belongs in this document.
The real corrected-host/installed-engine probe wrote `terminationStatus=9`,
`terminationReason=uncaughtSignal`, `signal=9`, duration 97 ms; the host returned
137. Its wrapper, home and symlinked prefix were newly allocated fixtures.

The first corrected-engine build stopped at the incompatible host FreeType
library. The source-built target dependency addresses that failure without
disabling Wine's font requirement. The completed source build produced engine
`wine-Wineversion11.17-36b6a2cf679f-x86_64-2471ca456b4c`, archive size 336,989,260
bytes, SHA-256 `d024d10dede017f62718773fe25bef358164fb57751c78f5ed6ab9fbf8877b2b`.
The install-tree x64/x86 probes returned expected exits 37/23. After extraction
to another temporary directory, they passed again (14.362 s / 0.286 s).
The resulting x86_64 loader, `ntdll.so` and FreeType dylib are unsigned local
build outputs; they are not Developer ID distribution candidates. FreeType's
load commands reference its `@rpath` identity and Apple's system library only,
and both required FreeType notice files were present after extraction.
Wrapper and winetricks archives were also built from source. The subsequent
metadata/SBOM additions were checked by executing their JSON generators; no
storage fetch, combined publishable manifest or production upload was performed.

The additional bootstrap failure is now **Verified and corrected locally**.
A fresh control with unmodified Wine bootstrap timed out at 180 seconds. Its
`+appwizcpl` trace reached the optional Mono installer URL and then the modal
installer; `drive_c/windows/syswow64/kernel32.dll` was still absent. Wine's
`loader/wine.inf.in` registers `mscoree`/`mshtml`, and
`dlls/mscoree/mscoree_main.c:DllRegisterServer` invokes Mono installation.
`dlls/appwiz.cpl/addons.c:install_addon` calls `DialogBoxW` when no bundled/cache
addon exists. This explains why interrupting bootstrap and then running a PE32
installer could yield `kernel32.dll c0000135`; it is not a recurrence of SIGKILL.

The production host now defers those optional registrations **only during
`--create-prefix`**, without a persisted DLL override or a Steam/game override.
Mono/.NET and Gecko-dependent applications still need separate component setup;
this baseline does not claim their availability. Desktop uses the official
`--winetricks -q steam` route, enabling Valve's supported silent installer mode.
The new production-host probe does not inject any test-only DLL overrides.
It requires both kernel32 architectures and executes both Windows command paths.
Extracted-layout validation now runs this probe in addition to the engine smoke.

Two fresh disposable production-host fixtures completed prefix bootstrap in
15.126 and 17.760 seconds. Both x64/x86 commands returned expected 37/23 statuses.
Both official Steam installations finished with status 0 (75.904 and 69.124
seconds) and produced `steam.exe`. The second fixture then launched Steam with
**no extra arguments** for a 120-second observation. Managed `steam.exe` and
`steamwebhelper.exe` processes were observed after the loader returned normal
exit 42. No owned on-screen window was reported by the scoped CoreGraphics
probe; screen-capture access was unavailable. There was no rendered-window or
interaction validation. All fixture Wine servers were stopped before deletion;
the everyday prefix and installed runtimes were excluded.

Final local packaging also passed: `build-wrapper.sh`, `build-winetricks.sh` and
`build-wine-engine.sh` produced `0.1.28-local` archives in `build/runtime-review`
(the engine reused the already-compiled source cache). Running
`PORTSIDE_RUNTIME_VERSION=0.1.28-local PORTSIDE_RUNTIME_BUILD_DIR="$PWD/build/runtime-review" ./scripts/build-runtime/validate-clean-layout.sh`
extracted all three archives, passed the engine x64/x86 checks, and completed the
production-host bootstrap in 16.686 seconds, followed by expected exits 37/23.
This is local assembly evidence, not signed production manifest evidence.

The release race is also corrected in source: app publication waits on Linux
for runtime assembly of `target_sha`, then validates source and workflow-run
binding in downloaded provenance and manifests. App-only changes assemble a
wrapper with the recipe-selected existing engine. Skipped change-filter runs
cannot pass; failures, cancellations, expired evidence and timeouts block the
release. Thirteen local regression tests and `actionlint` pass. No GitHub workflow,
storage publication, signing/notarization or backend registration was executed.

Additional commands included `brew install cabextract` for the official
winetricks route, `lipo`/`otool`/strict `codesign` inspection, and filtered
kernel-log/process/window inspection for disposable probes. No system trust
setting was changed. [STATUS](STATUS.md) records the remaining acceptance scope.

**Implemented but not end-to-end validated:** the new app and runtime must still
be validated together as final distribution artifacts, with a rendered interactive
login window and updater continuity in a disposable account. No process, test, signature, version probe or Dock icon in
this report establishes graphical Steam/game success. The installed runtime and
everyday prefix remain unchanged, so this source fix is not an installed repair.

## Changed-file inventory

| Area | Files |
| --- | --- |
| Desktop launch and reporting | `apps/desktop/Sources/Portside/PortsideApp.swift`, `apps/desktop/Sources/Portside/SteamProcessLauncher.swift`, `apps/desktop/Sources/PortsideCore/RuntimePipeline.swift`, `apps/desktop/Sources/PortsideCore/RuntimeLaunchReceipt.swift`, `apps/desktop/Sources/PortsideCore/PortsideRuntimePipeline.swift` |
| Isolated diagnostic logging | `apps/desktop/Sources/PortsideCore/PortsideCore.swift` |
| Host | `apps/runtime-host/Sources/PortsideRuntimeHost/main.swift`, `apps/runtime-host/README.md`, `apps/runtime-host/AGENTS.md` |
| Regression tests | `apps/runtime-host/Tests/PortsideRuntimeHostTests/LaunchDiagnosticsTests.swift`, `apps/desktop/Tests/PortsideCoreTests/SteamReadinessTests.swift`, `apps/desktop/Tests/PortsideCoreTests/PortsideCoreTests.swift`, `scripts/tests/test_wait_for_runtime.py` |
| Runtime configuration and dependencies | `runtime/wrapper-template/Contents/Resources/portside-runtime.json`, `upstream/dependencies.json` |
| Generated build cache exclusion | `.gitignore` (only `.cache/portside-wine/`) |
| Build and selection | `scripts/build-runtime/build-wine-engine.sh`, `scripts/build-runtime/build-freetype.sh`, `scripts/build-runtime/build-engine.sh`, `scripts/build-runtime/build.sh`, `scripts/build-runtime/resolve-engine.sh`, `scripts/build-runtime/changed-components.sh` |
| Engine validation | `scripts/build-runtime/validate-engine-execution.py`, `scripts/build-runtime/test-loader-layout.py`, `scripts/build-runtime/validate-clean-layout.sh`, `scripts/build-runtime/validate-steam-bootstrap.py` |
| Release source binding | `.github/workflows/release-production.yml`, `.github/workflows/build-runtime.yml`, `.github/workflows/ci.yml`, `scripts/wait_for_runtime.py` |
| Documentation and notices | This report, `docs/STATUS.md`, `docs/RUNTIME.md`, `docs/RELEASE.md`, `docs/SECURITY.md`, `docs/TESTING.md`, `docs/DECISIONS.md`, `docs/README.md`, `docs/THIRD_PARTY_LICENSES.md`, `THIRD_PARTY_NOTICES.md`, `RUNTIME_LICENSES.md` |
