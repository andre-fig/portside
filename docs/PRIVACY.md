# Privacy and data ownership

User Wine prefixes, Steam account state, games, saves and libraries belong to
the user. Runtime replacement or a license failure must not delete them.
Portside must not copy a native Steam session or report passwords, cookies,
tokens, Steam IDs, Apple IDs, window contents or screenshots.

## Implemented data paths

- Desktop licensing stores a device private key and signed token in device-local,
  non-synchronizing Keychain storage. The server receives a purchase key during
  activation and the device public key/proof; these are commercial account data.
- Backend Prisma models include customers, purchases, licenses, devices,
  activations, challenges and audit records. HMAC lookup avoids a plaintext
  purchase-key database column. Fulfillment writers are incomplete.
- The compatibility scanner reads bounded files under managed roots. Profiles
  and attempts can contain local executable paths; these raw files are not
  automatically safe to share.
- Main-app logging redacts selected sensitive patterns and rotates logs.
  Sentry filters app-reported events and disables default PII; initialization
  occurs before the install gate, including Debug. Delivery was not tested.
- RuntimeHost has separate, narrower redaction and no log rotation.
  Backend/landing raw error paths mean universal sanitized logging is not
  an implemented guarantee.

See source-linked controls and gaps in [SECURITY](SECURITY.md), the
[license protocol](LICENSING.md), and [backend model](BACKEND.md).
The signed offline deadline governs local license acceptance; it is not
instant online revocation. Expiry must request revalidation without data deletion.

## Unimplemented or unverified obligations

A comprehensive retention/deletion schedule, corresponding automated jobs,
public legal notice, support/deletion handling and service-side diagnostic
retention require explicit operational/legal evidence. The current cron logs
startup; it is not a data-retention job. Do not infer a retention window from an
old policy paragraph. Review exports and raw logs before any authorized sharing.
