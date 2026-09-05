# Portside landing

This directory is the monorepo source for the public site and checkout entry.
It uses React 19, TanStack Start/Router, Vite, Tailwind and Nitro's Node server
preset. Dependencies and commands are defined by [package.json](package.json),
[bun.lock](bun.lock), and [vite.config.ts](vite.config.ts). The former separate
landing repository is not a build dependency.

Start with [local agent rules](AGENTS.md), the [route map](src/routes/README.md),
[architecture](../../docs/ARCHITECTURE.md), and the
[commercial flow](../../docs/LICENSING.md). Current audit results and external
unknowns are in [STATUS](../../docs/STATUS.md).

## Local development

Run from `apps/landing`:

```sh
bun install --frozen-lockfile
bun run dev
```

For ordinary code changes:

```sh
bun run lint
bun run typecheck
bun run build
```

There is no package `test` command. The local pre-push hook installs the locked
dependencies and runs lint/typecheck/build. Railway deploys the service from
the connected `main` branch. A build proves compilation, not browser behavior,
a working payment, or deployment.
[Railway notes](../../docs/RAILWAY_DEPLOYMENT.md) distinguish source-controlled
settings from unknown external configuration.

## Code responsibilities

| Location                                                                                 | Responsibility                                                |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| [`src/router.tsx`](src/router.tsx), [`src/routes/__root.tsx`](src/routes/__root.tsx)     | Router and shared app shell/query/error handling              |
| [`src/routes`](src/routes)                                                               | Public file-based pages and route metadata                    |
| [`src/components/site`](src/components/site)                                             | Header, footer, supplied logo                                 |
| [`src/components/ui`](src/components/ui)                                                 | Reusable UI components                                        |
| [`src/lib/pricing.functions.ts`](src/lib/pricing.functions.ts)                           | Server-side display pricing                                   |
| [`src/lib/checkout.functions.ts`](src/lib/checkout.functions.ts)                         | Validated email input and server-side Stripe Checkout request |
| [`src/lib/order.functions.ts`](src/lib/order.functions.ts)                               | Current always-pending order-status placeholder               |
| [`src/server.ts`](src/server.ts), [`src/lib/error-capture.ts`](src/lib/error-capture.ts) | SSR failure recovery and error expansion                      |
| [`public`](public)                                                                       | Static assets; no application/runtime archives                |

`src/routeTree.gen.ts`, `.output/`, caches and dependency directories are generated.
Do not edit them manually or import Next.js/Remix route conventions. The shared
Vite configuration already supplies its plugins; duplicating them is unsafe.

## Commercial and UI limits

Checkout reads server-only Stripe/pricing environment names documented in
[LICENSING](../../docs/LICENSING.md). Missing credentials return an unconfigured
response. Do not put secrets in `VITE_*`, source, URLs, analytics, or browser
bundles. Raw Stripe error response logging and expanded SSR errors are existing
privacy risks that need separate code changes.

Checkout session creation is **Implemented but not end-to-end validated**.
Payment fulfillment is **Blocked** by the missing webhook/order/issuance/email
integration: order status always returns pending. The confirmed screen is
unreachable, and its resend control only shows a toast. Real Stripe payments,
Apple Pay and domain setup are **Unknown**. Display pricing does not query the
configured Stripe Price, so it can differ from Checkout.

English is the required product language. The root HTML declares `lang="en"`,
but existing route and checkout copy is largely Portuguese, including public
route slugs. That discrepancy is preserved as an implementation gap in this
documentation-only audit; future copy work must use English and explicitly
consider existing public URLs.

## Historical brief and preserved intent

The landing was imported in commit `ac5f4ea` on 2026-08-19. The former README
recorded source commit `3cb34d47f85016b87152b41f2ce040a4c723d91b` and contained
a product request rather than a statement of implemented behavior. The complete
brief remains in Git history. This audit consolidates its durable requirements:

- Preserve the supplied Portside logo, a clear responsive layout, accessible
  navigation, SEO metadata, and system fonts. Do not bundle proprietary fonts
  or copy Apple identity.
- Explain automatic setup and variable game compatibility; do not promise all
  games or anti-cheat systems work or imply Apple/Valve endorsement.
- Keep display/checkout pricing controlled by the server and send card data to
  Stripe. Validate HTTPS/domain/payment-method availability before an Apple Pay claim.
- Confirm purchases only through verified provider events; use idempotent
  persistence, unpredictable authenticated delivery references, issued licenses,
  temporary download URLs, and real email/resend behavior.
- Keep license copy/download and installation instructions behind confirmed
  fulfillment. Never expose full licenses in URLs, logs or analytics.
- Validate responsive/keyboard/screen-reader behavior and Safari/Chrome/Firefox;
  add appropriate commerce tests when implementing the missing path. The brief's
  webhook, replay, unpaid-success, delivery, email, and secret-exposure tests
  are requirements, not currently passing tests.

These requirements are **Planned** where the current code does not implement
them. Their prior presence in a README was not release evidence.
