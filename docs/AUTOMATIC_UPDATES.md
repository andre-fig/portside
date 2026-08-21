# Portside automatic updates

The local `scripts/package_app.sh` path is a development/validation bundle. It intentionally leaves the commercial feed, API and public keys empty and writes `PortsideBuildChannel=development`.

Customer releases use `.github/workflows/release-production.yml`. The protected GitHub `production` Environment must provide:

- `PORTSIDE_API_BASE_URL`
- `PORTSIDE_UPDATE_FEED_URL`
- `PORTSIDE_ARTIFACT_HOSTS`
- `PORTSIDE_SPARKLE_PUBLIC_KEY`
- `PORTSIDE_RUNTIME_MANIFEST_PUBLIC_KEY`
- `PORTSIDE_LICENSE_PUBLIC_KEY`
- `PORTSIDE_LICENSE_KEY_ID`
- `PORTSIDE_PUBLIC_BASE_URL`
- `PORTSIDE_PUBLIC_BUCKET` and `PORTSIDE_SECONDARY_PUBLIC_BUCKET`
- `PORTSIDE_CODESIGN_IDENTITY`
- `PORTSIDE_CODESIGN_P12_BASE64` and `PORTSIDE_CODESIGN_P12_PASSWORD`
- `PORTSIDE_CODESIGN_CERTIFICATE_PEM`
- `PORTSIDE_CODESIGN_CERTIFICATE_BASE64`
- `PORTSIDE_NOTARY_KEY_ID`
- `PORTSIDE_NOTARY_ISSUER_ID`
- `PORTSIDE_NOTARY_P8`
- `PORTSIDE_SPARKLE_PRIVATE_KEY`
- `PORTSIDE_MANIFEST_SIGNING_KEY`
- `PORTSIDE_RUNTIME_MANIFEST_JSON`

The private keys are written only to the ephemeral CI runner and are never copied into `Portside.app`. The production environment additionally requires `PORTSIDE_ADMIN_BEARER_TOKEN` and approval by the GitHub Environment protection rule.

The release sequence is:

```text
swift test --package-path apps/desktop
DATABASE_URL=postgresql://... npm --prefix apps/backend ci
./scripts/build_release.sh
./scripts/sign_release.sh
./scripts/notarize_release.sh
./scripts/validate_release_bundle.sh
./scripts/generate_appcast.sh
./scripts/publish_release.sh
```

Runtime manifests are signed before production publication. The desktop validates the Ed25519 signature, production channel, minimum Portside version, approved HTTPS host, SHA-256 and size before download. ETag/304 responses and a verified local cache preserve offline operation. The background `PortsideAgent` prepares runtime updates after the main app exits; installation happens on a later opening while Steam is stopped. The existing wrapper/prefix remain the rollback boundary.

The backend appcast is generated from `AppRelease` rows with `channel=production` and `status=production`; it returns the current release and two previous releases. A release is registered directly in production after signing, notarization and validation.

For the first real customer release, create Sparkle keys with the `generate_keys`
tool shipped in Sparkle, register the public key as
`PORTSIDE_SPARKLE_PUBLIC_KEY`, configure a macOS Developer ID identity and a
Team App Store Connect API Key for `notarytool`, then add the secrets above to
the GitHub `production` Environment. `PORTSIDE_NOTARY_P8` contains the
multiline contents of the downloaded `.p8` private key; it is materialized only
inside the ephemeral runner and removed after the job. The previous
`PORTSIDE_NOTARY_P8_BASE64` secret remains a temporary fallback for older
configurations. The Railway API and dual-bucket runtime storage are configured in
the single production environment. The
buckets remain private and the runtime manifest now uses the stable Portside
API `/v1/runtime/artifacts/production/<fileName>` route, which returns a
short-lived signed storage redirect. The API manifest must still be published
for production and a clean-install run must pass before an end-to-end customer
update can be claimed. Apple signing, notarization, customer release and final
appcast inspection remain separate release gates.
