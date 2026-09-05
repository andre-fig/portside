# Security and trust boundaries

This is the implemented trust model and its limits at the
[audit snapshot](STATUS.md). **Verified** requires recorded evidence;
**Implemented but not end-to-end validated** means code exists without complete
operational proof. External signing, storage, payment and service state is
**Unknown** unless separately evidenced; it was not queried during this audit.

## Trust roots and key ownership

| Purpose                    | Public configuration / verification                                                                                                                                                                   | Private material owner                                                                                                                                                            |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS application identity | Developer ID chain, signed bundle identifier, Team ID, version/build and code-directory hash in [`ApplicationInstallation.swift`](../apps/desktop/Sources/PortsideCore/ApplicationInstallation.swift) | Release CI/Keychain: `PORTSIDE_CODESIGN_IDENTITY`, certificate import secrets and notarization credentials. See [RELEASE.md](RELEASE.md).                                         |
| Sparkle app archive        | `SUPublicEDKey` and `SUFeedURL`, injected from `PORTSIDE_SPARKLE_PUBLIC_KEY` / `PORTSIDE_UPDATE_FEED_URL`                                                                                             | `PORTSIDE_SPARKLE_PRIVATE_KEY` in release secrets or protected Keychain; never bundled.                                                                                           |
| Runtime manifest           | `PortsideRuntimeManifestPublicKey`, injected from `PORTSIDE_RUNTIME_MANIFEST_PUBLIC_KEY`; backend `MANIFEST_SIGNING_PUBLIC_KEY`                                                                       | `PORTSIDE_MANIFEST_SIGNING_KEY` / `PORTSIDE_MANIFEST_SIGNING_KEY_FILE`, held by the signing runner/secret manager. Backend receives the public key only.                          |
| License token              | `PortsideLicensePublicKey`, `PortsideLicenseKeyID`; backend `LICENSE_SIGNING_PUBLIC_KEY_PEM`, `LICENSE_SIGNING_KEY_ID`                                                                                | Backend `LICENSE_SIGNING_PRIVATE_KEY_PEM`; a separate key/purpose from runtime manifests.                                                                                         |
| Device proof of possession | Random P-256 public key sent to the license API                                                                                                                                                       | Device private key in Secure Enclave where available, otherwise non-synchronizing Keychain; never shipped in the application.                                                     |
| Administration / storage   | [`AdminGuard`](../apps/backend/src/common/guards/admin.guard.ts), configured S3 client                                                                                                                | Backend `ADMIN_BEARER_TOKEN`, `LICENSE_HMAC_SECRET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`; release runner uses its separately configured names in [RELEASE.md](RELEASE.md). |

The source [app plist](../apps/desktop/Resources/Info.plist) contains empty public
key/feed placeholders. Release packaging injects public values before signing;
development packaging explicitly opts out of commercial behavior. Do not add
private keys, credentials or mutable runtime state to a signed app bundle.
Do not print secret values while validating configuration. Rotation requirements
are described in [KEY_ROTATION.md](KEY_ROTATION.md).

Sparkle and the desktop runtime verifier expect a base64-encoded 32-byte Ed25519
public key. The desktop license verifier also accepts an exact Ed25519
SubjectPublicKeyInfo PEM representation. Runtime and license formats are not
interchangeable; the names above identify separate trust roots. The embedded
agent receives API/host/runtime public configuration, not the license private
key or Sparkle signing material.

## Runtime authentication and download controls

[`PortsideManifestVerifier`](../apps/desktop/Sources/PortsideCore/CommercialInfrastructure.swift)
verifies Ed25519 over canonical JSON with `signature` replaced by `null`. It
requires exactly wrapper, engine and winetricks, unique component IDs, approved
HTTPS download hosts, positive sizes, hexadecimal SHA-256 and Portside source/
license metadata. Production clients require the production channel. Sikarugir
and raw GitHub binary URLs are rejected. This authenticates the signer's
assertions; it does not independently reproduce source checksums or validate an
SBOM's contents on the desktop.

The app combines the API host with `PortsideArtifactHosts`. The
[`SecureDownloader`](../apps/desktop/Sources/PortsideCore/PortsideCore.swift)
enforces HTTPS and the allowlist on artifact redirects, then size/SHA-256 before
an atomic cache-file write. Existing download-cache files are also hashed before
reuse. Runtime URLs may redirect through the backend to temporary storage URLs,
so both API and storage hosts must be approved. API JSON/license requests use
their supplied `URLSession`; the artifact-specific redirect delegate does not
protect those sessions.

[`PortsideBackendClient`](../apps/desktop/Sources/PortsideCore/PortsideBackendClient.swift)
authenticates the cached manifest before ETag reuse or offline fallback and
persists an authenticated minimum app version even when it blocks the current
build. A lower manifest version is accepted only when its signed
`rollbackVersion` equals the cached version; preparation performs a related
comparison against the installed version. This field represents an authorized
rollback _from_ that version in the current comparison logic. It is not an
unsigned operator bypass or a secure monotonic counter.

Limits that must remain visible:

- The runtime verifier decodes `schemaVersion` but does not reject unsupported
  schema numbers. `expectedKeyID` is optional and the normal runtime client does
  not supply it; cryptographic trust is pinned to the configured public key.
- Downloads are buffered in memory; the default 2 GiB maximum is checked after
  receiving the body. It is not a streaming memory bound.
- [`pendingRuntimeUpdate()`](../apps/desktop/Sources/PortsideCore/PortsideRuntimePipeline.swift)
  reads a local decoded index and checks paths, files and count. Application of
  that pending index does not repeat signature/size/hash verification. A local
  cache-tampering gap remains between preparation and installation.
- Archive extraction rejects absolute paths, backslashes and `..` in the tar
  listing. The desktop extractor does not explicitly validate symlink/hardlink
  target containment; do not describe it as a complete hostile-archive sandbox.
- Runtime layout validation checks expected files/options, not a fresh signature
  or complete engine hash at every launch. A writable per-user runtime is not a
  tamper-proof extension of the signed main application.

## Application relocation and replacement

Commercial startup refuses a mounted DMG, App Translocation, read-only bundle,
symlinked alternative or location other than `/Applications/Portside.app`.
Only Debug or signed `development` metadata provides the documented exemption.
This is a location gate, not notarization verification at each launch.

The [installation transaction](../apps/desktop/Sources/PortsideCore/ApplicationInstallationTransaction.swift)
verifies Developer ID, nested code and application identity. Replacing an
existing app requires matching Team ID and non-decreasing release and build
versions. It stages a complete `ditto` copy with resource forks, extended
attributes and ACLs; validates the code hash; rechecks the destination; and uses
exclusive rename or atomic exchange. Previous applications are retained, not
deleted. The install lock rejects symlinks and non-regular/multiply-linked files.

After a permission failure, macOS authorization copies into a private protected
directory, verifies the expected code hash, then runs that copy's installer.
The new app must be opened through LaunchServices before the old app exits.
DMG detachment is best effort and non-forced, only for a positively identified
source image. Unproven App Translocation origins are left mounted. Tests cover
injected identities/filesystem races; actual privilege prompts and all real
replacement scenarios require separate macOS acceptance.

[`sign_release.sh`](../scripts/sign_release.sh) signs nested Sparkle code,
agent, installer and main app with Hardened Runtime and timestamp, then performs
strict deep verification. The main [entitlements](../apps/desktop/Resources/Portside.entitlements)
are empty: this app is not App Sandbox isolated. The runtime-host
[entitlements resource](../apps/runtime-host/Resources/entitlements.plist) requests
disabled library validation, but the current
[wrapper builder](../scripts/build-runtime/build-wrapper.sh) does not apply it
through codesign. Its existence is not evidence of hardened/signed runtime code.

[`PortsideBundleComponents`](../apps/desktop/Sources/PortsideCore/PortsideBundleComponents.swift)
uses bundle metadata, expected IDs and resolved executable containment. Signature
status in component-resolution diagnostics is informational; it is not a
signature-enforcement gate for every helper launch. RuntimeHost likewise trusts
the manifest/installation path and reports signature state diagnostically.

## Update ordering, recovery and preservation

[`PortsideAppUpdatePreflight`](../apps/desktop/Sources/PortsideCore/PortsideAppUpdatePreflight.swift)
blocks runtime/Steam work until an explicit updater outcome. Late information
probes cannot start installation; a critical update, unresolved relaunch receipt
or installation deadline cannot silently release the gate. A signed manifest's
minimum app version remains mandatory offline. Sparkle archive signatures and
appcast transport/metadata are different trust properties; a critical appcast
marker alone is not the durable signed runtime minimum-version policy.

These guarantees scope the initial preflight. After a terminal outcome permits
bootstrap, the coordinator returns later Sparkle sessions to ordinary updater
policy; it does not apply another runtime-phase gate to every scheduled app
update. Later app-update/runtime overlap needs separate integration evidence.

The [activity lease](../apps/desktop/Sources/PortsideCore/PortsideRuntimeActivityLease.swift)
uses `flock`, `O_NOFOLLOW` and `O_CLOEXEC` to coordinate app preflight and runtime
preparation. Older workers are matched by current user, exact executable/argv,
kernel start time and running Developer ID/Team ID before SIGTERM. That narrowly
authenticated handoff does not stop compatibility or Steam processes.

Runtime installation has weaker recovery guarantees than application
relocation: it moves the active wrapper away before prefix work/final validation,
and pending application only attempts rollback on failure. There is no crash
journal or guaranteed previous-version selection. See [RUNTIME.md](RUNTIME.md)
for the current rollback defects. Prefixes and games remain outside replaceable
wrappers, but this separation alone is not proof of every interrupted migration.

Never remove a prefix, game, save, installed Steam session or license key to
repair an update. Never copy native macOS Steam account files. Scope process
termination to managed wrapper/prefix ownership, never a global name match.
The Steam readiness monitor also considers newly observed likely Wine/Steam
processes; this heuristic reinforces why window/process evidence needs manual
confirmation and is not a security identity check.

## Licensing and service access

[`CommercialInfrastructure.swift`](../apps/desktop/Sources/PortsideCore/CommercialInfrastructure.swift)
stores device keys with `ThisDeviceOnly`, non-synchronizing accessibility;
tokens use a device-local Keychain item. Activation verifies the Ed25519 token
before storing it. Offline validation checks the signed deadline; online renewal
signs a short-lived challenge with P-256. License contents and public device keys
are commercial/account data, not anonymous diagnostics.

The [backend license service](../apps/backend/src/modules/licenses/license.service.ts)
requires an active HMAC-indexed license, supports deactivation/revocation, verifies
the signed token and consumes a one-use challenge. Existing limits include an
application-level one-active-device check without a database-wide unique-active
constraint; renewal does not directly reject token expiry or recheck activation
status after challenge issuance. Full concurrent activation/revocation and
offline-revocation behavior is not end-to-end validated.

Administrative routes use a configured bearer token with timing-safe comparison.
Public appcast, runtime manifest and download routes do not require entitlement.
The [runtime redirect](../apps/backend/src/modules/artifacts/artifact.service.ts)
constrains production channel and archive filename, then signs an S3 key; it does
not establish that a matching object or published release exists. Manifest
publication authenticates and binds metadata to registered release records, but
administrative registration is not an independent storage-byte audit.

Checkout creates a Stripe session; there is no implemented payment webhook,
order-to-license issuance or delivery pipeline. The purchase return page must
never be treated as payment authorization. Deployment configuration and storage
permissions remain **Unknown** for this audit; see [BACKEND.md](BACKEND.md).

## Logs, diagnostics and remaining risks

Never log passwords, purchase keys, bearer tokens, cookies, Steam IDs, Apple IDs,
private keys, account files, full environment dumps or window contents.
[PortsideLogger](../apps/desktop/Sources/PortsideCore/PortsideCore.swift) redacts the
current home path, Windows user paths and selected credential patterns, and
rotates its own text logs. RuntimeHost has a separate, narrower regex sanitizer;
its captured output is truncated per message but its log has no rotation.
Regex redaction is not proof that arbitrary third-party output is safe to share.

[`SentryDiagnosticsService`](../apps/desktop/Sources/Portside/SentryDiagnosticsService.swift)
disables default PII and network tracking/breadcrumbs, removes user/context/extra
fields, filters tags, and sanitizes app-reported errors. It initializes in Debug
as well as Release before the installation gate. SDK-generated event fields and
delivery were not externally audited. Local profiles and game attempt JSON may
contain executable paths; the raw game-attempt writer does not apply the log
sanitizer before serialization. Review diagnostic exports before sharing them.

Backend [sanitization](../apps/backend/src/common/observability/sanitize.ts) is
not universal: [`main.ts`](../apps/backend/src/main.ts) logs bootstrap error
messages directly, and landing error handling includes raw Stripe error
responses and expanded server exception causes. Do not claim repository-wide
sanitized logging. [PRIVACY.md](PRIVACY.md) records privacy policy and operational
obligations; retention infrastructure must be proved, not inferred from a policy.

Source integrity remains a release obligation: locked Wine/winetricks snapshots,
reviewed synchronization, documented patches, checksums, provenance, SBOM and
license notices. Never patch `vendor/` manually, suppress validation failures,
reintroduce commercial Sikarugir binary fallbacks, mix staging/production, or
automatically promote a release as an agent. Existing automation and rollback
gaps are recorded in [RELEASE.md](RELEASE.md) and [STATUS.md](STATUS.md).
