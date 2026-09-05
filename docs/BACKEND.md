# Backend contracts

The backend is the NestJS/TypeScript control plane in
[`apps/backend`](../apps/backend). PostgreSQL stores commercial and release
records; a single S3-compatible configuration supplies private artifact URLs.
This describes source behavior, **Implemented but not end-to-end validated**.
Live Railway, database, bucket, and release state are **Unknown** in this audit;
see [STATUS](STATUS.md) for dated evidence and [ARCHITECTURE](ARCHITECTURE.md)
for the cross-component flows.

## Entry points and ownership

| Location                                                                                                           | Responsibility                                                                             |
| ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| [`src/main.ts`](../apps/backend/src/main.ts), [`app.module.ts`](../apps/backend/src/app.module.ts)                 | HTTP bootstrap, Helmet, DTO validation and a global throttler (60 requests per 60 seconds) |
| [`src/core/app-config.ts`](../apps/backend/src/core/app-config.ts)                                                 | Environment access and production startup checks                                           |
| [`src/database/prisma.service.ts`](../apps/backend/src/database/prisma.service.ts)                                 | Database connection lifecycle                                                              |
| [`modules/licenses`](../apps/backend/src/modules/licenses)                                                         | Activation, device challenges, token refresh, deactivation                                 |
| [`modules/artifacts`](../apps/backend/src/modules/artifacts)                                                       | Public presigned download endpoints                                                        |
| [`modules/runtime`](../apps/backend/src/modules/runtime)                                                           | Appcast, runtime manifest, source/build/release records                                    |
| [`modules/admin`](../apps/backend/src/modules/admin)                                                               | Bearer-protected administrative mutations                                                  |
| [`modules/synchronization`](../apps/backend/src/modules/synchronization)                                           | On-demand verified artifact ingestion into object storage                                  |
| [`src/worker.ts`](../apps/backend/src/worker.ts), [`jobs/sync.worker.ts`](../apps/backend/src/jobs/sync.worker.ts) | Stale-record reconciliation and optional GitHub workflow polling                           |
| [`src/cron.ts`](../apps/backend/src/cron.ts), [`jobs/cron.ts`](../apps/backend/src/jobs/cron.ts)                   | Scheduled entry point; currently logs startup only                                         |

DTOs are under each module's `dtos/`; services own behavior and controller
methods delegate. [`schema.prisma`](../apps/backend/prisma/schema.prisma)
separates customer/purchase/license/device/activation/challenge/revocation data
from source snapshots, builds, artifacts, app/runtime releases, manifests,
promotion/rollback history, synchronization, and audit models. A model's
presence does not prove a writer or operational workflow exists: purchase
issuance and comprehensive `AuditEvent` recording are not wired.

Current `Channel` accepts only `production`. The
[`production_only_channels` migration](../apps/backend/prisma/migrations/20260821030000_production_only_channels/migration.sql)
counts and preserves historical staging rows; it does not migrate or delete them.
Do not run a staging promotion sequence from older documentation. See
[DECISIONS](DECISIONS.md) and [RELEASE](RELEASE.md).

## Public HTTP contract

| Method and route                               | Behavior and boundary                                                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `GET /health`                                  | Liveness response; no storage, release, or payment validation                                                      |
| `GET /ready`                                   | Executes `SELECT 1` against PostgreSQL                                                                             |
| `GET /v1/appcast.xml`                          | Up to three production/superseded app releases, ordered by publication date                                        |
| `GET /v1/runtime/manifest`                     | Most recently published production runtime manifest                                                                |
| `GET /v1/artifacts/:id/download`               | JSON containing presigned URL, lifetime, checksum and size for an approved/production artifact                     |
| `GET /v1/runtime/artifacts/:channel/:fileName` | 302 to a presigned `runtime/production/<fileName>` object; production channel and three archive-name prefixes only |
| `GET /app/:channel/:fileName`                  | 302 for a registered production app ZIP or DMG; ZIP filename must match its release                                |
| `GET /app/:channel/latest`                     | Finds the active app release and redirects to its DMG                                                              |
| `POST /v1/licenses/activate`                   | Looks up an existing license HMAC and binds a P-256 device key                                                     |
| `POST /v1/licenses/challenge`                  | Creates a two-minute, one-use device challenge for an active license/activation                                    |
| `POST /v1/licenses/validate`                   | Verifies token and challenge proof, consumes challenge and returns a refreshed token                               |
| `POST /v1/licenses/deactivate`                 | Deactivates a device using its ID and the purchase key                                                             |

These public downloads/manifests do not require a license token. Presigning
does not prove that an object exists. In particular, the runtime filename
route performs no database/release lookup. All artifact paths use one S3 client;
there is no secondary-bucket failover. Redirects use `no-store` and `nosniff`;
the runtime URL lifetime is clamped to 60–900 seconds. The generic artifact-ID
route uses 300 seconds. See
[`artifact.service.ts`](../apps/backend/src/modules/artifacts/artifact.service.ts).

Appcast and manifest responses implement SHA-256 ETags, conditional 304s and
short public caching. Production refuses checked-in fixture fallback; absent
published database records produce unavailable responses. Development can
read [`manifests`](../apps/backend/manifests); those files are examples, not
published-release evidence.

## Authenticated release operations

All routes below are `POST /v1/admin/<suffix>`, guarded by
[`AdminGuard`](../apps/backend/src/common/guards/admin.guard.ts), which compares
`Authorization: Bearer` against `ADMIN_BEARER_TOKEN` using a timing-safe helper.
There is no implemented OIDC/mTLS gateway or per-actor authorization model.

| Suffix                         | State transition                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| `source-snapshots/register`    | Upserts source/snapshot as verified from administrator-provided provenance                       |
| `builds/register`              | Records build status and verified snapshot relations; matching retries repair snapshot links     |
| `artifacts/register-published` | Registers metadata for existing runtime objects without downloading them again                   |
| `artifacts/sync`               | Downloads an approved-host URL, verifies digest/optional signature, uploads and records artifact |
| `artifacts/:id/promote`        | Marks a verified/approved artifact production after checking snapshot/build state                |
| `artifacts/:id/rollback`       | Deprecates one artifact and promotes an eligible prior component version                         |
| `releases/register`            | Requires successful build and eligible artifacts; directly marks release/artifacts production    |
| `manifests/publish`            | Verifies and binds a signed manifest to its production release; supersedes prior manifest        |
| `releases/:id/rollback`        | Attempts to restore a target runtime manifest and records rollback                               |
| `app-releases/register`        | Registers an app release directly as production and supersedes the previous app release          |
| `app-releases/:id/rollback`    | Marks current app release rolled back and restores an eligible target                            |
| `licenses/:id/revoke`          | Revokes license and active activations; stores a revocation reason                               |

The metadata-only registration path validates component filename, approved API
URL, snapshot/source provenance, successful build and retry identity. It trusts
the authorized caller's size/checksum and build evidence; it does not inspect
the remote object's bytes. The ingest path does read bytes, refuses redirects,
checks `MAX_DOWNLOAD_BYTES` and SHA-256, optionally verifies a supplied artifact
signature, and writes the single bucket. Its in-memory download has a size
check after reading, so it is not a streaming memory bound. Source cloning is
owned by the GitHub [upstream workflow](../.github/workflows/sync-upstreams.yml),
not the Railway worker or cron placeholder.

[`publishManifest`](../apps/backend/src/modules/runtime/runtime.service.ts)
requires Portside build identity, three component entries, approved HTTPS
URLs, positive safe sizes, SHA-256, source/license fields, and a production
release. It verifies Ed25519 over canonical JSON with `signature: null` and
binds component, filename, size and checksum to that release. The optional
`MANIFEST_SIGNING_KEY_ID` must match when configured. Serving a stored manifest
checks structure again, but does not repeat cryptographic verification; the
desktop remains responsible for verifying every received manifest. There is
no backend monotonic-version/downgrade check.

App-release registration validates URL/metadata and stores `edSignature`; it
does not fetch the ZIP or cryptographically verify its Sparkle signature.
Neither runtime registration nor app registration performs human graphical
acceptance. Do not infer those guarantees from an administrative status value.

## Licensing and known integration limits

The [commercial licensing contract](LICENSING.md) describes purchase-to-device
boundaries. The service stores an HMAC and support prefix, not plaintext
purchase keys. Activation expects an already-issued database license; no
checkout/webhook/license issuance endpoint currently creates it.

Two release inconsistencies require tests and a separate implementation change:

- Runtime rollback requires the target to have a `published` manifest, while
  normal publication marks prior manifests `superseded`. An ordinary previous
  release therefore fails the target precondition.
- The appcast includes superseded releases, while the corresponding app
  download route accepts only production releases. Older feed enclosures can
  become unavailable. Changing the feed does not prove Sparkle can downgrade.

License activation's one-device rule is an application transaction query;
the schema has uniqueness on `(licenseId, deviceId)`, not a global constraint
for one active device. Concurrent activation needs real database testing.
Refresh verifies a one-use challenge and current license state but does not
directly reject the supplied token's expiry or recheck activation status after
challenge issuance. Document/test that policy before claiming immediate
deactivation enforcement. These are source findings, not demonstrated exploits.

## Local checks and deployment boundary

Run from `apps/backend` for ordinary backend development:

```sh
npm ci
npm run prisma:validate
npm run typecheck
npm run lint
npm test
npm run build
```

`build` first runs `prisma generate`, then compiles TypeScript without specs.
`npm run dev` starts the API through `tsx`; `npm start` runs `dist/main.js`.
Database setup/migrations require a separately authorized local or disposable
PostgreSQL instance; `npm run prisma:migrate:deploy` is a mutation, not a test.
Never point tests, worker, or migration commands at production by assumption.

[`vitest.config.ts`](../apps/backend/vitest.config.ts) selects adjacent
`src/**/*.spec.ts` files. Current tests cover mocked service/controller paths,
P-256 activation inputs, download-key construction, ETags, workflow metadata,
and pure policies. Pure policy tests do not prove the service enforces those
policies in a real transaction. No checked-in integration suite validates a
real database, S3, Stripe, release rollback, or concurrent activation.

[`CI`](../.github/workflows/ci.yml) runs production policy, Prisma validation
and the backend build. It does not run the full local lint/typecheck/unit suite.
See [TESTING](TESTING.md) for actual audit results, and
[RAILWAY_DEPLOYMENT](RAILWAY_DEPLOYMENT.md) for Docker/configuration ownership.
