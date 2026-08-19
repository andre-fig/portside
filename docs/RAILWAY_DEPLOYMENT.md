# Railway deployment runbook

Create separate Railway projects for `staging` and `production`. In each
project create independent services for:

1. API using `apps/backend/railway.api.json`.
2. PostgreSQL with automated backups and a tested restore procedure.
3. Private S3-compatible Bucket/object storage, with a second provider or
   bucket configured for replication.
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
Use different values and key IDs for staging and production.

Before adding a public custom domain, verify `/health`, `/ready`, TLS, signed
artifact URLs, appcast content type and manifest signature. The API should
return a temporary object-storage URL rather than proxying large files.

Production is connected to `andre-fig/portside` on the `main` branch. Railway
deploys the three application services automatically after each push; the
`Verify Railway` GitHub workflow waits for the public API healthcheck after CI.
The production API is available at
`https://api-production-6d06.up.railway.app`.
