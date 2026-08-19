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
service and run the migration command once as a controlled release step:

```sh
railway link --project <staging-project-id> --environment staging
railway run --service api npm --prefix apps/backend run prisma:migrate:deploy
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

This workspace has not been deployed to Railway. The commands above are a
runbook and require the owner's authenticated Railway CLI session.
