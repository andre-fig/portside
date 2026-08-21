# Commercialization readiness

Portside keeps the validated Wine/Steam pipeline intact and adds a separate
commercial control plane. The app bundle contains Portside code only. Runtime
components are selected by a signed manifest and downloaded from Portside-owned
HTTPS storage using short-lived URLs.

There is one Railway operational environment and one customer release channel:

- `development`: local Debug builds may use the pinned official sources for
  validation. No production license bypass is compiled into Release.
- `production`: the only release channel in the Railway project, database,
  buckets and API. GitHub Actions uses its protected `production` Environment
  for secrets and approvals.

The repository does not contain Railway IDs, passwords, signing keys, a
Developer ID identity, a Sparkle private key or a license-signing private key.
Those values belong in Railway/CI secret stores and the macOS Keychain.

Commercial release gates:

1. Legal review of Portside, Wine, winetricks, runtime and trademark terms.
2. Artifact provenance, source notices and checksums complete.
3. macOS validation of the real Steam window with the approved runtime.
4. Developer ID signing, Hardened Runtime, notarization and stapling.
5. Sparkle EdDSA appcast and runtime-manifest signatures verified.
6. Production activation/update/rollback tests pass.
7. Authenticated registration of the release in the production API.

Local/CI command sequence (the variables are intentionally not supplied here):

```sh
PORTSIDE_VERSION=1.0.0 \
PORTSIDE_API_BASE_URL=https://api.<your-domain> \
PORTSIDE_UPDATE_FEED_URL=https://api.<your-domain>/v1/appcast.xml \
PORTSIDE_ARTIFACT_HOSTS=downloads.<your-domain> \
PORTSIDE_SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
PORTSIDE_RUNTIME_MANIFEST_PUBLIC_KEY="$MANIFEST_PUBLIC_KEY" \
PORTSIDE_LICENSE_PUBLIC_KEY="$LICENSE_PUBLIC_KEY" \
PORTSIDE_LICENSE_KEY_ID=license-2026-01 \
./scripts/build_release.sh

PORTSIDE_VERSION=1.0.0 \
PORTSIDE_CODESIGN_IDENTITY='Developer ID Application: <team>' \
PORTSIDE_RUNTIME_MANIFEST_INPUT=/secure/unsigned-runtime-manifest.json \
PORTSIDE_MANIFEST_SIGNING_KEY_FILE=/secure/manifest-signing-key.pem \
./scripts/sign_release.sh

PORTSIDE_VERSION=1.0.0 \
PORTSIDE_NOTARY_KEY_ID=<APP_STORE_CONNECT_KEY_ID> \
PORTSIDE_NOTARY_ISSUER_ID=<APP_STORE_CONNECT_ISSUER_ID> \
PORTSIDE_NOTARY_KEY_PATH=/secure/AuthKey_<APP_STORE_CONNECT_KEY_ID>.p8 \
./scripts/notarize_release.sh

SPARKLE_BIN="$PWD/.build/artifacts/sparkle/Sparkle/bin" \
PORTSIDE_UPDATES_DIR="$PWD/build/releases/updates" \
./scripts/generate_appcast.sh
```

Publish only after production validation. The authenticated release workflow
registers the signed release directly in the production API and can roll back
to a signed previous version; the application never carries the admin
credential.

```sh
PORTSIDE_VERSION=1.0.0 PORTSIDE_PUBLIC_BUCKET=<approved-bucket> \
PORTSIDE_SECONDARY_PUBLIC_BUCKET=<approved-secondary-bucket> \
PORTSIDE_UPDATE_CHANNEL=production PORTSIDE_CONFIRM_PRODUCTION=YES ./scripts/publish_release.sh

curl --fail --request POST \
  --header "Authorization: Bearer $PORTSIDE_ADMIN_BEARER_TOKEN" \
  --header 'Content-Type: application/json' \
  --data '{}' "$PORTSIDE_API_BASE_URL/v1/admin/app-releases/register"
```

For runtime assets, use the source/build/release endpoints documented in
`docs/BACKEND.md`. Register only a successful Portside build, validate it on a
real Mac, then register the production release and publish its signed manifest
with `POST /v1/admin/manifests/publish`. Production publication also requires
`PORTSIDE_CONFIRM_PRODUCTION=YES`; the publishing script writes each object to
both approved buckets and keeps prior versions for rollback.

The Railway API and dual object storage are configured for production runtime,
and the production runtime workflow produces signed evidence in both buckets.
This does not claim a customer release: Developer ID signature, notarization,
real-Mac GUI acceptance and an end-to-end desktop download still require their
external result to be produced and recorded. The current buckets are private;
the backend exposes the short-lived signed redirect used by production runtime
manifests, but the API manifest still needs to be published and validated end
to end before rollout.
