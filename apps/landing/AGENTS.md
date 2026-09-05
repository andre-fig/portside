# Landing agent instructions

Read [the root rules](../../AGENTS.md), [the local overview](README.md),
[licensing](../../docs/LICENSING.md), and [security](../../docs/SECURITY.md).

- Responsibility: the public React/TanStack Start site, server-side pricing,
  and Stripe Checkout session creation. The local monorepo is the build source;
  do not restore a dependency on the former separate landing repository.
- Entry points: `src/router.tsx`, `src/routes/__root.tsx`, `src/start.ts`, and
  `src/server.ts`. Routes live in `src/routes`; site identity/layout in
  `src/components/site`; reusable UI in `src/components/ui`; commercial server
  functions in `src/lib`. Follow the [route guide](src/routes/README.md).
- `vite.config.ts` selects Nitro's Node server preset and the custom SSR entry.
  Its shared Vite configuration supplies the existing plugins; do not duplicate
  them. Keep server credentials out of browser-visible `VITE_*` configuration.
- `getOrderStatus` currently always returns `pending`. The confirmation UI and
  resend toast do not implement webhook validation, issuance, delivery, or email.
  Never unlock a purchase from a browser redirect or invent payment success.
- Preserve customer data; keep full licenses, payment data, signed URLs, and
  secrets out of logs/analytics. The existing raw Stripe/SSR error logging is a
  known limitation, not a pattern to copy.
- New or changed product copy must be English. Existing Portuguese copy is
  recorded in [STATUS](../../docs/STATUS.md); translating it is a separate code
  change, outside a documentation-only task. Do not silently rename public routes.
- Keep the supplied logo and notices. Never promise universal game/anti-cheat
  compatibility or imply affiliation with Apple or Valve.

From this directory, the normal code-change checks are:

```sh
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run build
```

There is no package test command or checked-in commerce test suite. Browser,
accessibility, Stripe test-mode, and delivery checks must be recorded separately.
Do not run installs/builds when the task forbids generated-directory writes.
Do not edit `node_modules/`, `.output/`, `src/routeTree.gen.ts`, or generated
build output manually; do not use `bun run format` for unrelated files.

Completion requires relevant checks, actual route/browser evidence for UI claims,
and documentation updated in the same change set. Update [STATUS](../../docs/STATUS.md)
and [DECISIONS](../../docs/DECISIONS.md) when milestones or architecture change.
State when validation needs external credentials, domain configuration, or a
published app. No task here authorizes deployment or release promotion by default.
