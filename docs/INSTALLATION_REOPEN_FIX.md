# Installation reopen correction — 2026-09-05 UTC

The published 0.1.24 installation attempt copied Portside into Applications but
its quarantine metadata remained. The observed replacement process launched
under App Translocation and returned to the installation gate. The application
log recorded repeated `movingToApplications` → `failed` transitions; it did not
record a specific installation error. Both the downloaded and installed bundles
passed strict signature verification and had the same code directory hash.

## Implementation

Before replacing the existing app, the installer now validates the private
staged copy's Developer ID identity, asks Gatekeeper to assess execution with
`spctl --assess --type execute`, and revalidates the identity. Only after those
checks pass does it release the staged copy's `com.apple.quarantine` attributes.
It preserves all other metadata, does not follow symlinks, and verifies the
signature again before the existing atomic replacement transaction continues.
The download, prior application, runtime, prefixes and game data are untouched
by this preparation. Rejection leaves the existing installation in place.

The UI offers **Install and Open**, displays **Installing Portside…** and
**Opening Portside…**, and provides **Open Portside** when installation succeeded
but reopening failed. That action verifies the installed app and retries opening
without copying again. Installation failures now log a fixed stage/reason and
the helper's numeric exit status, without command text or personal paths.

Quarantine handling follows the approach used by
[Sparkle's file manager](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUFileManager.m).
Portside additionally requires the staged copy to pass the system's execution
assessment before releasing its quarantine metadata.

## Verification and limits

- `swift test --package-path apps/desktop`: 117 discovered, 116 passed,
  one optional installed Sparkle network probe skipped.
- `swift build --package-path apps/desktop`: passed.
- `./scripts/validate-production-policy.sh` and `git diff --check`: passed.
- Regression tests cover quarantine preservation on the source/unrelated symlink
  target, retention of unrelated extended attributes, rejection before mutation,
  Gatekeeper failure preserving an existing installation, and a verified retry
  of opening without recopying.
- A separate temporary harness compiled the actual core sources and ran the
  production transaction against a quarantined copy of the authentic 0.1.24 app.
  Real Developer ID checks and Gatekeeper passed. LaunchServices returned the
  exact disposable destination, without translocation; Accessibility reported
  a native application window. Only that test process was closed.

The graphical probe's destination was deliberately outside Applications, so the
commercial location gate stopped before runtime, license or Steam initialization.
It proves staged trust/quarantine preparation and LaunchServices reopening. It
does not establish a complete customer bootstrap, new UI interaction, real
administrator authorization, or rendered Steam/game acceptance.

## Automatic newer-version handoff — 2026-09-10 UTC

When an older copy starts outside Applications, the desktop detects a newer
installed copy and opens it automatically without presenting an install/open
choice. Both copies must have valid signatures and the same application/publisher
identity; the installed release and build must satisfy the existing no-downgrade
rules. A newer copy detected during the install transaction follows the same
handoff, with fresh signature/identity/version validation before opening.

No copy or downgrade is attempted when preflight finds the newer installed app.
The old process exits only after LaunchServices successfully opens the installed
copy, then the existing deferred disk-image ejection behavior applies. Actual
opening failures retain the retry UI. Signature, publisher and version conflicts
never qualify for automatic opening.

Regression fixtures cover startup selection, equal/older versions, build-only
updates, mixed version/build ordering, invalid signatures/publishers, destination
changes before opening, a newer app arriving during installation, and reopening
failure without ejection. They do not replace real signed-DMG/LaunchServices
acceptance in a graphical session.
