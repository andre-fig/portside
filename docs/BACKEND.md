# Portside backend

`apps/backend/` is an independent NestJS/TypeScript service with PostgreSQL via
Prisma. The API, worker, sync Cron Job, database and private object storage
are separate Railway services or resources. Railway's ephemeral filesystem is
never treated as artifact storage.

The Prisma schema includes customers, purchases, licenses, devices,
activations, one-use challenges, artifacts, versions, channels, manifests,
upstream sources, sync executions, audit events and revocations. License keys
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

The example environment is intentionally nonfunctional. PostgreSQL, object
storage and all signing secrets must be supplied separately.
