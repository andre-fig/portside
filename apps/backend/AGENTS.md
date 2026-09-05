# Backend agent instructions

Read [the root rules](../../AGENTS.md), [architecture](../../docs/ARCHITECTURE.md),
[backend contracts](../../docs/BACKEND.md), and the relevant sections of
[security](../../docs/SECURITY.md) and [release](../../docs/RELEASE.md) before editing.

- Responsibility: NestJS HTTP API, license activation, artifact redirects,
  release metadata, and workflow reconciliation backed by PostgreSQL/Prisma.
- Entry points: `src/main.ts` starts HTTP; `src/worker.ts` starts
  `src/jobs/sync.worker.ts`; `src/cron.ts` starts the current log-only cron job.
- Keep configuration in `src/core`, shared guards/policies in `src/common`,
  Prisma integration in `src/database`, and feature logic in `src/modules`.
  Keep controllers thin, DTOs in `dtos/`, and unit specs beside their subjects.
- Schema changes require an accompanying Prisma migration. Preserve existing
  purchases, license records, activations, and release history. The current
  schema accepts only `production`; the legacy-channel migration preserves
  old rows. Do not reinterpret those rows as a usable staging environment.
- Preserve signed manifest checks, approved HTTPS hosts, size/checksum
  validation, object-key validation, and the public/private key boundary.
  License private keys belong in server secrets; manifest private keys belong
  in CI/administrative secrets. Neither belongs in a client bundle or logs.
- Do not add automatic release promotion or mix staging and production. Existing
  release registration changes production state; a task to inspect or test it
  does not authorize invoking it against a deployed service.
- A public artifact redirect is not proof of license entitlement or object
  existence. The runtime route does not query release records. A mocked
  presigner test does not prove an S3 download.
- The landing checkout has no completed webhook-to-license fulfillment path.
  Do not mistake schema models or activation APIs for license issuance.
- Keep API messages and future product UI in English. Never log raw keys,
  tokens, payment responses, signed URLs, customer data, or Steam data.

From this directory, the normal code-change checks are:

```sh
npm ci
npm run prisma:validate
npm run typecheck
npm run lint
npm test
npm run build
```

`npm run build` generates Prisma code and `dist/`; `npm ci` writes
`node_modules/`. Do not run these in a documentation-only audit that forbids
generated-directory writes. Never edit `node_modules/`, `dist/`, or generated
Prisma clients manually. Run migrations only against an explicitly authorized
database; starting the worker also mutates database records and may contact GitHub.

Completion requires the relevant checks and documented results/limitations,
matching DTO/service/schema behavior, and documentation updated with the code.
Update [STATUS](../../docs/STATUS.md) when an evidenced milestone changes and
[DECISIONS](../../docs/DECISIONS.md) when architecture changes. Real DB,
storage, payment, release, and concurrency behavior require integration evidence.
