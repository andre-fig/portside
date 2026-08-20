# Railway deployment runbook

Create separate Railway projects for `staging` and `production`. In each
project create independent services for:

1. API using `apps/backend/railway.api.json`.
2. PostgreSQL with automated backups and a tested restore procedure.
3. Private S3-compatible Bucket/object storage, with a second bucket configured
   for replication. The current Portside project has `portside-artifacts` and
   `portside-artifacts-secondary`; their generated physical bucket names and
   credentials come from Railway, not from the repository.
4. Sync worker using `apps/backend/railway.worker.json`.
5. Upstream sync Cron Job using `apps/backend/railway.cron.json`.

Set the service root for each application service to `apps/backend` and use
`Dockerfile` as the Dockerfile path. Set `DATABASE_URL` from the PostgreSQL
service. The API runs `npx prisma migrate deploy` as its Railway pre-deploy
command, inside the service network where the private PostgreSQL hostname is
available.

```sh
railway link --project <staging-project-id> --environment staging
railway up --service api
railway up --service sync-worker
railway up --service upstream-cron
```

Do not paste IDs or tokens into the repository. Required variables are listed
in `apps/backend/.env.example`: database URL, public API URL, S3 endpoint/bucket
credentials, allowlists, HMAC secret, license signing key pair and IDs,
manifest public key, Sparkle public key, offline grace period and size limits.
The sync worker additionally needs a read-only `PORTSIDE_GITHUB_TOKEN`,
`PORTSIDE_GITHUB_REPOSITORY=andre-fig/portside` and
`PORTSIDE_RUNTIME_WORKFLOW=build-runtime.yml` to reconcile workflow runs. It
records workflow/test state but cannot promote or publish a release.
Use different values and key IDs for staging and production.
Configure both primary and secondary S3-compatible credentials; a production
deployment must never rely on Railway's ephemeral filesystem. Store the
manifest signing private key only in the CI/administrative secret store and
expose only `MANIFEST_SIGNING_PUBLIC_KEY` to the API.

Before adding a public custom domain, verify `/health`, `/ready`, TLS, signed
artifact URLs, appcast content type and manifest signature. The API should
return a temporary object-storage URL rather than proxying large files.

Runtime publication is staging-only by default. The authenticated release
sequence is source snapshot, successful build, staging release, validation,
explicit promotion and signed manifest publication. Do not point a production
manifest at an upstream source URL; runtime files must already be built and
promoted into Portside object storage.

## Runtime build secrets from Railway

`Build Portside Runtime` executes on GitHub's macOS runner, so it cannot read
Railway variables automatically. The GitHub Environment named `staging` must
contain a copy of the Railway bucket connection values. The mapping is:

| GitHub Actions secret | Railway source |
| --- | --- |
| `PORTSIDE_PUBLIC_BUCKET` | primary bucket credential `bucketName` |
| `PORTSIDE_S3_ACCESS_KEY_ID` | primary bucket credential `accessKeyId` |
| `PORTSIDE_S3_SECRET_ACCESS_KEY` | primary bucket credential `secretAccessKey` |
| `PORTSIDE_S3_REGION` | primary bucket credential `region` |
| `PORTSIDE_S3_ENDPOINT` | primary bucket credential `endpoint` |
| `PORTSIDE_SECONDARY_PUBLIC_BUCKET` | secondary bucket credential `bucketName` |
| `PORTSIDE_SECONDARY_S3_ACCESS_KEY_ID` | secondary `accessKeyId` |
| `PORTSIDE_SECONDARY_S3_SECRET_ACCESS_KEY` | secondary `secretAccessKey` |
| `PORTSIDE_SECONDARY_S3_REGION` | secondary `region` |
| `PORTSIDE_SECONDARY_S3_ENDPOINT` | secondary `endpoint` |

`PORTSIDE_RUNTIME_ARTIFACT_URL_PREFIX` is the HTTPS virtual-host URL of the
primary bucket followed by `runtime/staging/`, for example
`https://<bucketName>.t3.storageapi.dev/runtime/staging/`. The bucket remains
the Railway S3-compatible service; the GitHub secrets only grant the runner
temporary access to publish there. The runtime workflow uses separate primary
and secondary credentials and never writes to Railway's ephemeral service
filesystem.

The private `PORTSIDE_MANIFEST_SIGNING_KEY` exists only in GitHub Actions. Its
matching public key is `MANIFEST_SIGNING_PUBLIC_KEY` in the Railway API. Do
not put either private signing key or bucket secret in Git, logs, or a chat
message. A new key pair requires updating the Railway public key before the
next signed manifest build.

Production is connected to `andre-fig/portside` on the `main` branch. Railway
deploys the three application services automatically after each push; the
`Verify Railway` GitHub workflow waits for the public API healthcheck after CI.
The production API is available at
`https://api-production-6d06.up.railway.app`.
