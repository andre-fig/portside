# Privacy boundary

Portside does not collect Steam passwords, cookies, tokens, Steam IDs, Apple
IDs or a user's personal Steam library. The license service receives a license
key only during activation, a random device public key and the minimum signed
license claims. The private device key stays in the Mac Keychain with
`ThisDeviceOnly`, non-synchronizable storage; Secure Enclave is attempted when
available.

Diagnostics are allowlisted and sanitized. Logs never intentionally contain
credentials or account identifiers. Backend audit events retain activation,
deactivation, revocation and administrative artifact decisions for the
documented retention window, after which personal records should be deleted or
anonymized through the operator's retention job.

The 14-day offline grace period is configurable. If it expires, Portside asks
for a connection without deleting games, the prefix or Steam data. A license
failure must never be used as a reason to modify or corrupt the runtime.

Before commercial launch, publish the legal privacy notice, retention period,
support/deletion process and applicable regional disclosures.
