# Desktop instructions

Inherit the [root rules](../../AGENTS.md). Read
[architecture](../../docs/ARCHITECTURE.md), [runtime](../../docs/RUNTIME.md),
[security](../../docs/SECURITY.md), and the task-specific
[test matrix](../../docs/TESTING.md) before editing; verify the current code.

- **Responsibility:** native English macOS setup/launch UI and shared runtime,
  installation, licensing, update and compatibility logic. Keep reusable logic
  in `Sources/PortsideCore`; `Sources/Portside` orchestrates UI and SDK adapters.
- **Entry points:** `PortsideApp.swift`; `PortsideUpdateCoordinator.swift` for
  Sparkle; `PortsideAgent/main.swift` for compatibility or runtime preparation;
  `PortsideInstaller/main.swift` for app relocation. `Package.swift` declares
  all four products; Resources plists define bundle identity/configuration.
- **Invariants:** preserve location → awaited app update → license/runtime →
  Steam ordering. Commercial builds require writable
  `/Applications/Portside.app`; Debug/development exemptions are explicit.
  Resolve helpers through Foundation bundle metadata. Keep SDK dependencies out
  of the core. Runtime and Sparkle updates have different keys and lifecycles.
- **Sensitive boundaries:** no private keys in bundles, no native Steam session
  copying, no prefix/library removal during repair/license failure/rollback, no
  blanket process-name termination. Preserve existing worktree and user data.
  Maintain signature, manifest, host, checksum, minimum-version and lease checks.
- **Validation:** from repository root run `swift test --package-path apps/desktop`
  and `swift build --package-path apps/desktop`. Changes to host/bundle resolution
  also require `swift test --package-path apps/runtime-host`. Runtime/release
  changes additionally need `./scripts/validate-production-policy.sh`; always
  use `git diff --check`. `./scripts/package_app.sh` makes a development bundle;
  it is not commercial release evidence.
- **Test limits:** `PORTSIDE_VALIDATION_APP_BUNDLE` enables an opt-in real Sparkle
  network probe; it is skipped by default and is not an update installation test.
  Do not set it during a local-only audit. Use disposable test homes/fixtures;
  never prepare a clean-install test by deleting an everyday user's data.
- **Known traps:** runtime pending application lacks fresh cryptographic
  revalidation; runtime rollback is best effort; renderer inventory still uses
  legacy `SharedSupport/wine` while installation uses `SharedSupport/engine`.
  Check [STATUS.md](../../docs/STATUS.md) before claiming these are resolved.
  Process/window detection is `visibleButUnverified`, not proven Steam UI/gameplay.
- **Generated files:** `.build/`, DerivedData and packaged bundles/DMGs are outputs;
  do not edit dependency checkouts, generated plists or signed bundles to fix
  source. Update build inputs instead; preserve Swift dependency locks.
- **Done:** relevant checks and recorded results, no sensitive/generated payload
  in the diff, English UI, preserved data, and matching documentation. Update
  `docs/STATUS.md` for milestones and `docs/DECISIONS.md` for accepted/replaced
  architecture. State which GUI, certificate or external-service checks remain
  unperformed. Do not publish/promote automatically or mix channels.
