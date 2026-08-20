# Portside backend

`apps/backend/` is an independent NestJS/TypeScript service with PostgreSQL via
Prisma. The API, worker, sync Cron Job, database and private object storage
are separate Railway services or resources. Railway's ephemeral filesystem is
never treated as artifact storage.

The Prisma schema includes customers, purchases, licenses, devices,
activations, one-use challenges, source snapshots, runtime builds, artifacts,
releases, channels, manifests, promotions, rollbacks, upstream sources, sync
executions, audit events and revocations. License keys
are represented by an HMAC and a support prefix; the plaintext key is not
stored.

Endpoints:

```text
GET  /health
GET  /ready
GET  /v1/appcast.xml
GET  /v1/runtime/manifest
GET  /v1/artifacts/:id/download
POST /v1/licenses/activate
POST /v1/licenses/challenge
POST /v1/licenses/validate
POST /v1/licenses/deactivate
POST /v1/admin/artifacts/sync
POST /v1/admin/artifacts/:id/promote
POST /v1/admin/artifacts/:id/rollback
POST /v1/admin/licenses/:id/revoke
POST /v1/admin/source-snapshots/register
POST /v1/admin/builds/register
POST /v1/admin/releases/register
POST /v1/admin/releases/:id/promote
POST /v1/admin/releases/:id/rollback
POST /v1/admin/manifests/publish
```

`/ready` checks PostgreSQL. Rate limiting, Helmet, strict DTO validation,
allowlisted HTTPS sources, storage-key validation and sanitized logs are
enabled by default. Admin routes use a Railway secret and are never called by
the app. Replace the initial bearer guard with the organization's approved
OIDC/mTLS gateway before production.

Run locally:

```sh
cd apps/backend
cp .env.example .env
npm ci
npx prisma generate
npx prisma migrate deploy
npm run typecheck
npm run lint
npm run build
npm test
npm start
```

Unit tests use the `*.spec.ts` convention and live beside the source file they
cover. DTOs are grouped under each feature's `dtos/` directory. The backend
build excludes specs, while CI runs type-checking, linting, tests and the
production build.

The source synchronization workflow owns source cloning and opens a pull
request; Railway does not clone upstream source into ephemeral storage. The
worker reconciles stale synchronization, source-snapshot and build records and
polls the authorized Portside runtime workflow when `PORTSIDE_GITHUB_TOKEN` is
configured. Each observed run is upserted as a `RuntimeBuild` with the
Portside commit, workflow URL/ID, environment, test result and build status.
It never promotes a release; promotion and rollback remain authenticated
operations.
The release sequence is `register source snapshot` → `register successful
build` → `register staging release` → `publish signed staging manifest` →
`record clean-install acceptance` → `promote release` → `publish signed
production manifest`. Promotion rejects a build without `testResult.cleanInstall
== "passed"` or without a published staging manifest. The manifest endpoint
verifies the Ed25519 signature and requires the release record for the selected
channel. A production manifest cannot be published from a staging or failed
release.
The example environment is intentionally nonfunctional. PostgreSQL, both
object-storage locations and all signing secrets must be supplied separately.
