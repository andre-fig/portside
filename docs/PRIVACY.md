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

The desktop sends setup failures and the successful Steam-window checkpoint to
Sentry. Events contain the Portside version/build, setup stage, stable error
code, macOS version, architecture, renderer and bounded readiness flags. The
Sentry integration removes user, context and extra data before transmission;
purchase keys, Steam credentials, cookies, tokens, Steam IDs, file contents
and account identifiers are not sent. Event IDs and sanitized failure reasons
are also written to the local Portside log so a failed upload can be diagnosed.

The 14-day offline grace period is configurable. If it expires, Portside asks
for a connection without deleting games, the prefix or Steam data. A license
failure must never be used as a reason to modify or corrupt the runtime.

Before commercial launch, publish the legal privacy notice, retention period,
support/deletion process and applicable regional disclosures.
