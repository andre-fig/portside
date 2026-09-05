# Public routes

TanStack Start uses file-based routing here. The current routes are:

| File                                 | URL            | Responsibility                                                       |
| ------------------------------------ | -------------- | -------------------------------------------------------------------- |
| [`__root.tsx`](__root.tsx)           | Shared shell   | HTML document, query provider, metadata and error/not-found handling |
| [`index.tsx`](index.tsx)             | `/`            | Product overview, compatibility/pricing sections and purchase entry  |
| [`comprar.tsx`](comprar.tsx)         | `/comprar`     | Email form and Stripe Checkout session request                       |
| [`sucesso.tsx`](sucesso.tsx)         | `/sucesso`     | Polls `session_id` order status; never proof of payment by itself    |
| [`suporte.tsx`](suporte.tsx)         | `/suporte`     | Public support information                                           |
| [`termos.tsx`](termos.tsx)           | `/termos`      | Public terms text                                                    |
| [`privacidade.tsx`](privacidade.tsx) | `/privacidade` | Public privacy text                                                  |

Keep the shared `<Outlet />` in the root layout. Do not substitute Next.js or
other frameworks' routing conventions for this TanStack route tree. `src/routeTree.gen.ts` is generated and must not be edited
manually. See [the component overview](../../README.md) and
[local agent rules](../../AGENTS.md).

The older guide listed generic example routes that do not exist in this
repository; the table above replaces them with the actual route map. Route
names remain unchanged by this audit. Existing visible copy is largely
Portuguese despite the required English product language and `lang="en"`;
translation/routing changes require an explicit implementation change.

[`order.functions.ts`](../lib/order.functions.ts) currently always returns
`pending`; the success screen's confirmed/download/license branch is
unreachable and its email-resend control is only a toast. See
[licensing and fulfillment](../../../../docs/LICENSING.md) before altering that flow.
