# Commercialization readiness

Portside keeps the validated Wine/Steam pipeline intact and adds a separate
commercial control plane. The app bundle contains Portside code only. Runtime
components are selected by a signed manifest and downloaded from Portside-owned
HTTPS storage using short-lived URLs.

There are three operational environments:

- `development`: local Debug builds may use the pinned official sources for
  validation. No production license bypass is compiled into Release.
- `staging`: a separate Railway project, database, bucket prefix, update feed,
  signing key IDs and test licenses.
- `production`: a separate Railway project, database, bucket and key set. A
  staging result and an authorized promotion are required before production.

The repository does not contain Railway IDs, passwords, signing keys, a
Developer ID identity, a Sparkle private key or a license-signing private key.
Those values belong in Railway/CI secret stores and the macOS Keychain.

Commercial release gates:

1. Legal review of Portside, Wine, winetricks, runtime and trademark terms.
2. Artifact provenance, source notices and checksums complete.
3. macOS validation of the real Steam window with the approved runtime.
4. Developer ID signing, Hardened Runtime, notarization and stapling.
5. Sparkle EdDSA appcast and runtime-manifest signatures verified.
6. Staging activation/update/rollback tests pass.
7. Manual authorized promotion to production.

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

PORTSIDE_VERSION=1.0.0 PORTSIDE_NOTARY_PROFILE=portside-notary \
./scripts/notarize_release.sh

SPARKLE_BIN="$PWD/.build/artifacts/sparkle/Sparkle/bin" \
PORTSIDE_UPDATES_DIR="$PWD/build/releases/updates" \
./scripts/generate_appcast.sh
```

Publish only after staging validation. Use the authenticated admin API to
promote an approved artifact and to roll back to a signed previous version;
the application never carries the admin credential.

```sh
PORTSIDE_VERSION=1.0.0 PORTSIDE_PUBLIC_BUCKET=<approved-bucket> \
PORTSIDE_SECONDARY_PUBLIC_BUCKET=<approved-secondary-bucket> \
PORTSIDE_UPDATE_CHANNEL=staging ./scripts/publish_release.sh

curl --fail --request POST \
  --header "Authorization: Bearer $PORTSIDE_ADMIN_BEARER_TOKEN" \
  --header 'Content-Type: application/json' \
  --data '{}' "$PORTSIDE_API_BASE_URL/v1/admin/artifacts/<artifact-id>/promote"
```

For runtime assets, use the source/build/release endpoints documented in
`docs/BACKEND.md`. Register only a successful Portside build, create a staging
release, validate it on a real Mac, promote it explicitly, then publish the
signed manifest with `POST /v1/admin/manifests/publish`. Production publication
also requires `PORTSIDE_CONFIRM_PRODUCTION=YES`; the publishing script writes
each object to both approved buckets and keeps prior versions for rollback.

The Railway API and dual object storage are configured for runtime staging, and
the staging runtime workflow has produced signed evidence in both buckets.
This does not claim a customer release: Developer ID signature, notarization,
production promotion, real-Mac GUI acceptance and an end-to-end desktop
download still require their external result to be produced and recorded. The
current buckets are private, so the desktop download proxy/redirect remains a
required infrastructure step before rollout.
