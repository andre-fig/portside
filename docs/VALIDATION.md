# Manual clean-install and graphical acceptance

This protocol requires a real macOS display and an operator. It records required
observations; it does not assert a passing run. Automated checks are in
[TESTING](TESTING.md); current evidence is in [STATUS](STATUS.md).

## Current source-inferred blocker

The wrapper template retains `Contents/SharedSupport/prefix/.gitkeep`, so the
archive contains that directory. The script links its external prefix into the
existing directory instead of replacing it; the link nests inside the directory.
The host then uses a different prefix from the script's external `steam.exe` and
preservation-marker checks. This is an inference from template/build/script
source, not an executed failure. Resolve and test this fixture-layout contract
in a separate code change before relying on the script for complete acceptance.
The protocol below remains the required acceptance target.

## Preconditions and trust limits

Use a dedicated Apple-silicon Mac test account and a newly allocated disposable
root. Never delete an everyday prefix, license, library or Steam session to
simulate first launch. Select the exact runtime artifact/version, source/build
evidence and authentic signed manifest; independently verify its trust before
executing archives.

The [clean-install script](../scripts/validate-clean-install.sh) requires
`PORTSIDE_RUNTIME_ARTIFACTS_DIR` and `PORTSIDE_RUNTIME_VERSION`; set
`PORTSIDE_CLEAN_ROOT` to a new disposable location. Optional
`PORTSIDE_PREVIOUS_RUNTIME_ARTIFACTS_DIR` and `PORTSIDE_PREVIOUS_RUNTIME_VERSION`
enable a previous-wrapper scenario. It deletes its selected clean root and
stops processes matched to that root/prefix. Its path checks do not make an
existing user directory disposable.

The script validates structure, component hashes/sizes and a nonempty signature
field. **It does not cryptographically authenticate that signature**, and it
extracts supplied archives. It is an operator test using already trusted
artifacts, not the production desktop verifier.

The [manual workflow](../.github/workflows/validate-clean-install.yml) uses
`self-hosted`, `macos`, `arm64` labels and needs a logged-in GUI session plus
Accessibility permission. GitHub steps normally have no interactive TTY: the
script leaves the window available, exits 2 at its first confirmation and does
not record GUI acceptance. Only an authorized interactive Terminal session can
complete the prompts. No acceptance was run during this audit.

## Required observations

1. For complete desktop acceptance, follow [BOOTSTRAP_VALIDATION](BOOTSTRAP_VALIDATION.md)
   first: commercial app install, Sparkle preflight and license gates.
2. Confirm Rosetta handling through Apple when absent, new managed prefix
   creation and Steam installation from Valve through winetricks.
3. Confirm the initial Steam updater finishes and that first execution closes.
4. Open the same wrapper again; inspect an actual rendered Steam login window.
5. Confirm keyboard and mouse interaction in the login controls. A process,
   executable, Dock icon or window-list entry is not proof.
6. Confirm `steamwebhelper` functionality and Steam persistence after updater
   completion. Close Steam and confirm no unintended relaunch loop.
7. With an authorized test account, install, launch and close the control game.
   The existing script requests App ID `3139440` (GunZ: The Duel). Record a
   usable rendered scene; this establishes nothing about other games.
8. Exercise subsequent launch/offline behavior, main-app exit, and applicable
   app/runtime update sequencing. Preserve all user state.
9. When testing prior/current wrappers, verify the script's synthetic prefix
   marker and manually inspect continuity. This scenario does not exercise the
   desktop's pending-index or backend rollback implementation by itself.

## Evidence and failure reporting

Record UTC date, source commit, app/runtime versions, artifact hashes/build IDs,
Mac/macOS/toolchain, command/result and each observed manual step. Keep logs
sanitized; do not attach credentials, Steam account identifiers, window contents
or screenshots to repository documentation.

Report the precise failing stage: prefix creation, winetricks installation,
updater, first shutdown, second opening, window creation, rendered login, input,
Steam persistence or game execution. The monitor's `visibleButUnverified`
state is not `uiReady`; manual confirmation must be separately evidenced.

A script result or a `cleanInstall` database field alone is not proof of the
whole customer flow. Current release registration records `not_verified`;
see [RELEASE](RELEASE.md). Preserve failures and blockers in STATUS instead of
turning pending requirements into a success matrix.
