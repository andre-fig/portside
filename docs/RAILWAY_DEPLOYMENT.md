# Railway deployment contract

This is the repository's deployment configuration and validation runbook, not
an inventory of live services. Railway project membership, variables, domains,
watch patterns, GitHub integration, backups, bucket policy and deployed revision
are **Unknown**: no external service was queried during this audit. Historical
operational statements in the previous version are retained in Git history;
[STATUS](STATUS.md) is the current dated snapshot.

## Source-controlled service configuration

| Component      | Repository evidence                                                                                               | Configured behavior                                                                         |
| -------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| API            | [`railway.api.json`](../apps/backend/railway.api.json)                                                            | Dockerfile build; `node dist/main.js`; `/health`; `npx prisma migrate deploy` before deploy |
| Worker         | [`railway.worker.json`](../apps/backend/railway.worker.json)                                                      | Same image; `node dist/worker.js`; stale-record/GitHub reconciliation                       |
| Cron           | [`railway.cron.json`](../apps/backend/railway.cron.json)                                                          | `node dist/cron.js`; schedule `17 */6 * * *`; implementation currently logs once            |
| PostgreSQL     | [`schema.prisma`](../apps/backend/prisma/schema.prisma) and [migrations](../apps/backend/prisma/migrations)       | Required persistence; live provisioning/backups are not represented by these files          |
| Object storage | [`AppConfig`](../apps/backend/src/core/app-config.ts)                                                             | One private S3-compatible connection; no secondary failover                                 |
| Landing        | [`vite.config.ts`](../apps/landing/vite.config.ts), [`build-landing.yml`](../.github/workflows/build-landing.yml) | Nitro Node SSR bundle in `.output`; Bun install/lint/typecheck/build in CI                  |

Backend service roots must make the backend Dockerfile's relative `COPY` paths
resolve against `apps/backend`. The [Dockerfile](../apps/backend/Dockerfile)
uses Node 22 Debian stages, installs locked npm dependencies, generates Prisma,
compiles TypeScript, copies runtime output/manifests, and runs as the `node`
user. It does not use the service filesystem as persistent artifact storage.
The API's migration pre-deploy command needs an authorized database and a usable
Prisma CLI; the production image omits dev dependencies, where the Prisma CLI
is declared. CLI availability and migration execution need deployment evidence.

The landing Node start entry is `.output/server/index.mjs`, as recorded by the
existing deployment runbook and selected Nitro preset. There is no checked-in
landing Railway configuration defining service roots, watch patterns or a
start command. The prior runbook described `apps/landing` as root, its
install/build commands, `/` healthcheck and deployment from `main` gated by
`Build Landing (Railway deploy gate)`. Treat those as intended setup to verify,
not current Railway facts.

## Configuration ownership

Only variable/secret names belong in documentation. Source behavior is defined
by [`app-config.ts`](../apps/backend/src/core/app-config.ts),
[`runtime.service.ts`](../apps/backend/src/modules/runtime/runtime.service.ts),
[`sync.worker.ts`](../apps/backend/src/jobs/sync.worker.ts), and the
[example environment](../apps/backend/.env.example); never copy actual values.

| Purpose                       | Names                                                                                                                                                                  |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| API/database                  | `NODE_ENV`, `PORT`, `DATABASE_URL`, `PUBLIC_BASE_URL`                                                                                                                  |
| Administrative authentication | `ADMIN_BEARER_TOKEN`                                                                                                                                                   |
| Storage                       | `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_FORCE_PATH_STYLE`                                                             |
| Artifact policy               | `ALLOWED_SOURCE_HOSTS`, `PORTSIDE_ARTIFACT_HOSTS`, `PORTSIDE_APP_HOSTS`, `MAX_DOWNLOAD_BYTES`, `PORTSIDE_RUNTIME_SIGNED_URL_TTL_SECONDS`, `UPSTREAM_SIGNING_KEYS_JSON` |
| Runtime verification          | `MANIFEST_SIGNING_PUBLIC_KEY`, optional `MANIFEST_SIGNING_KEY_ID`                                                                                                      |
| App feed/service host         | `PORTSIDE_APPCAST_URL`, optional provider-supplied `RAILWAY_PUBLIC_DOMAIN`                                                                                             |
| License service               | `LICENSE_HMAC_SECRET`, `LICENSE_SIGNING_PRIVATE_KEY_PEM`, `LICENSE_SIGNING_PUBLIC_KEY_PEM`, `LICENSE_SIGNING_KEY_ID`, `OFFLINE_GRACE_DAYS`                             |
| Worker                        | `PORTSIDE_GITHUB_TOKEN`, `PORTSIDE_GITHUB_REPOSITORY`, `PORTSIDE_RUNTIME_WORKFLOW`, `SYNC_WORKER_POLL_MS`, `SYNC_WORKER_TIMEOUT_MS`                                    |

`ALLOWED_SOURCE_HOSTS` must be nonempty at production startup, but the artifact
ingest path uses `PORTSIDE_ARTIFACT_HOSTS`. `OFFLINE_GRACE_DAYS` is loaded but
actual license deadlines use each database row. `SPARKLE_PUBLIC_KEY` and
`LOG_LEVEL` appear in the example environment without a current backend reader.
Do not describe them as implemented backend verification/logging controls.
Landing Stripe/pricing variables are listed in [LICENSING](LICENSING.md).

GitHub macOS runners do not inherit Railway variables. The runtime/release
publisher uses a separately configured GitHub `production` Environment:

| Publisher name                  | Equivalent backend connection name |
| ------------------------------- | ---------------------------------- |
| `PORTSIDE_PUBLIC_BUCKET`        | `S3_BUCKET`                        |
| `PORTSIDE_S3_ACCESS_KEY_ID`     | `S3_ACCESS_KEY_ID`                 |
| `PORTSIDE_S3_SECRET_ACCESS_KEY` | `S3_SECRET_ACCESS_KEY`             |
| `PORTSIDE_S3_REGION`            | `S3_REGION`                        |
| `PORTSIDE_S3_ENDPOINT`          | `S3_ENDPOINT`                      |

The name `PORTSIDE_PUBLIC_BUCKET` does not establish a public bucket policy.
`PORTSIDE_MANIFEST_SIGNING_KEY` remains in CI/administrative secret storage;
the backend receives the corresponding public key only. License token signing
is separate and requires its private key on the backend. See [RELEASE](RELEASE.md)
for the complete signing/publishing variable contract.

## Validation runbook and release boundaries

1. Use the local backend checks in [BACKEND](BACKEND.md) and landing checks in
   its [README](../apps/landing/README.md). Do not run migrations against an
   unspecified database. The current application accepts production only;
   legacy staging rows do not constitute a separate environment.
2. For an explicitly authorized deployment, review the actual Railway service
   root, Dockerfile/config selection, branch, watch patterns, start command,
   database target and secret ownership. The old runbook used Railway CLI
   `link`/`up`, but repository inspection cannot validate installed CLI behavior
   or the target account; no deploy command is executed by this audit.
3. Validate `/health` for liveness and `/ready` for database access. Confirm the
   deployed revision separately: `/health` exposes no revision. Validate TLS,
   manifest signature, appcast content type, and complete signed artifact
   downloads against expected size/SHA-256. Avoid logging presigned query strings.
4. The stable runtime route is `/v1/runtime/artifacts/production/<fileName>`;
   it signs a redirect to `runtime/production/<fileName>`. Desktop policy must
   permit both API and storage redirect hosts. The app routes use
   `/app/production/<fileName>` and `/app/production/latest` (DMG).
5. Runtime publication also needs registered source snapshots, successful build,
   artifact/release records and signed manifest publication. An uploaded archive
   or responding healthcheck does not complete desktop discovery, Sparkle,
   notarization, or graphical clean-install acceptance.

[`Verify Railway`](../.github/workflows/deploy-railway.yml) follows successful
CI for relevant backend/deploy changes and polls a configured public `/health`
URL. It does not deploy, check `/ready`, validate the exact served revision,
prove backups, or inspect Stripe/storage. The landing workflow produces a build
artifact; its title alone does not prove a Railway gate is configured. Actual
publication behavior and manual authorization boundaries are in
[RELEASE](RELEASE.md); rollback precondition gaps are in [BACKEND](BACKEND.md).
