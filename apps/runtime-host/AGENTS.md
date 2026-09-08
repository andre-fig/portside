# Runtime-host instructions

Inherit the [root rules](../../AGENTS.md). Read
[runtime](../../docs/RUNTIME.md), [architecture](../../docs/ARCHITECTURE.md) and
[security](../../docs/SECURITY.md), then check current source before changes.

- **Responsibility / entry point:** `Sources/PortsideRuntimeHost/main.swift` is
  the maintenance helper in the Sikarugir candidate and the primary launcher in
  legacy direct-Wine wrappers, not the desktop agent or
  an independent user app. `Package.swift` supports focused tests; production
  wrapper assembly uses `scripts/build-runtime/build-wrapper.sh` and the
  versioned `runtime/wrapper-template` from repository root.
- **Local architecture:** Foundation resolves the app bundle and its JSON
  resource. Explicit `integration: sikarugir` routes winetricks to the contained
  original launcher/SDK with the required silent setting; unsupported verbs and
  interactive configuration fail before launch. Steam opens through the original Sikarugir application
  entry point; the maintenance host rejects normal Steam launches. Absent integration retains the legacy
  direct-Wine path. Unknown integrations and missing/escaping Sikarugir code
  fail closed. Prefix maintenance remains a bounded host command, with addon
  deferral confined to wineboot and no Wine 11 CEF policy applied to Sikarugir.
  Preserve bundle identity and resolved executable containment.
- **Invariants:** use `Process` executable URLs and argument arrays, not shell
  command strings. The host does not fetch a prebuilt engine; the approved
  winetricks Steam verb obtains Steam from Valve. The existing direct-Wine host
  is a legacy implementation, not the intended substitute for Sikarugir.
  Follow [the integration contract](../../docs/SIKARUGIR_INTEGRATION.md);
  do not invent launcher arguments or enable renderer flags without the actual
  upstream components and validation. Keep runtime output sanitized. Preserve
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
