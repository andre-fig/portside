# Key rotation

Keep separate key pairs and IDs for Sparkle app updates, runtime manifests and
license tokens. The app embeds public keys only. Private keys belong in the
CI/Railway secret store or the macOS Keychain used by Sparkle tooling.

Rotation procedure:

1. Generate a new pair in the approved offline/CI key system.
2. Assign a new `keyId` and publish the new public key in a release that still
   accepts the previous key.
3. Sign a new appcast/manifest/token with the new key and verify it in the
   production publication checks.
4. Promote only after old and new clients have been tested.
5. Keep the old public key for the documented overlap window, then revoke it
   from the backend and CI workflow.
6. Record the event in `AuditEvent` without recording private material.

Never pass Sparkle's private key as a command-line argument or commit it. Do
not reuse a license-signing key for manifests or app updates.
