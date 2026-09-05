# Signing-key rotation

Separate Sparkle, runtime-manifest and license-token signing keys. The app
contains public verification material; private keys belong to CI/Keychain or
the backend secret store for license signing. See [SECURITY](SECURITY.md) and
[RELEASE](RELEASE.md) for exact configuration names.

## Current implementation and limits

The normal desktop configuration injects one runtime public key, one Sparkle
public key and one license public key/key ID. A suggested overlap window in
older documentation did not establish a deployed multi-key rotation mechanism.
Do not assume old and new clients can accept both keys without implementation
and interoperability tests. External key inventory/revocation is Unknown.

## Planned operator procedure

For an authorized rotation, first design and test how the old client trusts
the transition: ship compatible public verification material, validate old/new
client and token/manifest/archive combinations, and retain a usable recovery
path. Only then change the private signer and retire old verification material
after an explicitly defined overlap period. Record public key IDs, accepted
client versions, dates and sanitized results; never record private material.

Do not reuse one key across purposes or pass Sparkle private material on the
command line. No general rotation CLI, enforced overlap window or automated
AuditEvent integration for key rotation is implemented by this runbook.
