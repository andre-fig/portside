# Runtime-host instructions

Inherit the [root rules](../../AGENTS.md). Read
[runtime](../../docs/RUNTIME.md), [architecture](../../docs/ARCHITECTURE.md) and
[security](../../docs/SECURITY.md), then check current source before changes.

- **Responsibility / entry point:** `Sources/PortsideRuntimeHost/main.swift` is
  the native launcher inside the generated wrapper, not the desktop agent or
  an independent user app. `Package.swift` supports focused tests; production
  wrapper assembly uses `scripts/build-runtime/build-wrapper.sh` and the
  versioned `runtime/wrapper-template` from repository root.
- **Local architecture:** Foundation resolves the app bundle and its JSON
  resource; argument arrays select Wine, wineboot, winetricks or a Windows
  program. Preserve bundle identity and resolved executable containment.
- **Invariants:** use `Process` executable URLs and argument arrays, not shell
  command strings. The host does not fetch a prebuilt engine; the approved
  winetricks Steam verb obtains Steam from Valve. Keep baseline WineD3D,
  alternative renderer flags disabled, and runtime output sanitized. Preserve
  existing prefixes, games, credentials and user data; never copy native Steam.
- **Validation:** from repository root, `swift test --package-path apps/runtime-host`
  and `swift build --package-path apps/runtime-host`; host/interface changes also
  require desktop tests/build and `./scripts/validate-production-policy.sh`.
  Use [RUNTIME.md](../../docs/RUNTIME.md) for the complete source/assembly checks.
- **Known traps:** tests run the compiled host with dummy Wine in a disposable
  bundle/home, proving bundle discovery, termination diagnostics and output
  handling, not Steam execution. Signature diagnostics are not a
  host authorization gate. `Resources/entitlements.plist` is not applied by the
  current wrapper build. Child output redaction is heuristic. Do not claim
  hardened runtime, Steam UI or game compatibility without matching evidence.
- **Generated files:** `.build/`, wrapper archives and assembled bundles are
  outputs. Never edit them or `vendor/` snapshots to fix a build; change owned
  source/build inputs or a documented upstream patch.
- **Done:** relevant checks recorded, English errors/UI, no widened data access,
  source/template/desktop contracts consistent, and docs updated together.
  Record milestone/decision changes in `docs/STATUS.md` / `docs/DECISIONS.md`;
  identify required graphical/external checks. Never publish/promote implicitly.
