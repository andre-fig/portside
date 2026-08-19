# Railway deployment runbook

Create separate Railway projects for `staging` and `production`. In each
project create independent services for:

1. API using `backend/railway.api.json`.
2. PostgreSQL with automated backups and a tested restore procedure.
3. Private S3-compatible Bucket/object storage, with a second provider or
   bucket configured for replication.
4. Sync worker using `backend/railway.worker.json`.
5. Upstream sync Cron Job using `backend/railway.cron.json`.

Set the service root to the repository root so the Dockerfile path remains
`backend/Dockerfile`. Set `DATABASE_URL` from the PostgreSQL service and run
the migration command once as a controlled release step:

```sh
railway link --project <staging-project-id> --environment staging
railway run --service api npm --prefix backend run prisma:migrate:deploy
railway up --service api --config backend/railway.api.json
railway up --service sync-worker --config backend/railway.worker.json
railway up --service upstream-cron --config backend/railway.cron.json
```

Do not paste IDs or tokens into the repository. Required variables are listed
in `backend/.env.example`: database URL, public API URL, S3 endpoint/bucket
credentials, allowlists, HMAC secret, license signing key pair and IDs,
manifest public key, Sparkle public key, offline grace period and size limits.
Use different values and key IDs for staging and production.

Before adding a public custom domain, verify `/health`, `/ready`, TLS, signed
artifact URLs, appcast content type and manifest signature. The API should
return a temporary object-storage URL rather than proxying large files.

This workspace has not been deployed to Railway. The commands above are a
runbook and require the owner's authenticated Railway CLI session.
