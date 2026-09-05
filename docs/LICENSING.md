# Commercial licensing and checkout

This document connects purchase fulfillment to the device-license protocol.
Source licensing and distribution notices remain in [root LICENSING](../LICENSING.md),
[RUNTIME_LICENSES](../RUNTIME_LICENSES.md), and
[THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). See [SECURITY](SECURITY.md)
for trust boundaries and [STATUS](STATUS.md) for the dated operational snapshot.

## What is implemented

| Step                                                                       | Status                                   | Repository evidence and limits                                                                                                                                                                       |
| -------------------------------------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Server-side price display                                                  | Implemented but not end-to-end validated | [`pricing.functions.ts`](../apps/landing/src/lib/pricing.functions.ts) reads environment pricing; it does not fetch the configured Stripe Price                                                      |
| Stripe Checkout session creation                                           | Implemented but not end-to-end validated | [`checkout.functions.ts`](../apps/landing/src/lib/checkout.functions.ts) validates email and calls Stripe server-side; missing credentials return an explicit unconfigured state                     |
| Real payment, Apple Pay, domain/Stripe setup                               | Unknown                                  | Not verified during this audit; configuration names and UI text are not evidence                                                                                                                     |
| Payment webhook, purchase persistence, license issuance and email delivery | Planned                                  | No handler or integration found in backend/landing; the historical landing brief requested these steps                                                                                               |
| Fulfillment after checkout                                                 | Blocked                                  | [`getOrderStatus`](../apps/landing/src/lib/order.functions.ts) always returns `pending`; no confirmed response can currently reach the UI                                                            |
| Existing-license activation, challenge, refresh and deactivation           | Implemented but not end-to-end validated | [`LicenseService`](../apps/backend/src/modules/licenses/license.service.ts), [`PortsideLicenseClient`](../apps/desktop/Sources/PortsideCore/PortsideBackendClient.swift), and activation/token tests |
| Commercial third-party authorization and obligations                       | Unknown                                  | Notices and source inventories exist; approval for a particular commercial release was not verified                                                                                                  |

The checkout uses a configured Stripe Price when `STRIPE_PRICE_ID` is present;
otherwise it builds price data from server-side environment settings. Displayed
pricing always comes from those local settings, so a configured Stripe Price
can disagree with the displayed amount. `checkoutReady` only means a secret
string is present. The current random idempotency key identifies each request;
it does not provide stable retry identity or webhook fulfillment idempotency.

The success route polls order status. Its confirmed branch contains license
copy/download controls, an app download link, and text claiming an email was
sent, but that branch is unreachable with the current status function. The
resend control only shows a toast. Neither the browser redirect nor these UI
controls prove payment or delivery. The backend has `Customer`, `Purchase`,
and `License` models, including a unique provider/reference pair on purchases,
but no implemented checkout writer or license issuer.

## Existing-license protocol

1. A previously issued purchase key must already have an active database row.
   The server normalizes its format and derives HMAC-SHA-256 with
   `LICENSE_HMAC_SECRET`; it stores the digest and a support prefix. The full
   purchase key is not a database column.
2. The desktop generates a P-256 device key in Keychain, using Secure Enclave
   when available. Activation sends the purchase key and public key. The API
   validates the P-256 key before creating a device and checks for another
   active device in a transaction.
3. The API returns an Ed25519-signed token with license ID, device ID, plan,
   issuance/expiry, offline deadline and key ID. The offline interval comes
   from the license row's `offlineGraceDays`; the configuration property
   `OFFLINE_GRACE_DAYS` does not currently set existing rows.
4. The desktop verifies the signature, configured key ID, device binding and
   response/token offline agreement before Keychain persistence. It can accept
   a locally verified token until its offline deadline without contacting the API.
5. On refresh, the desktop obtains a one-use challenge, signs it with its
   device key, and submits the token/proof. The server verifies both signatures,
   atomically consumes the challenge and rechecks license state before issuing
   a new token. Administrative revocation changes the license and activations.

See [`CommercialInfrastructure.swift`](../apps/desktop/Sources/PortsideCore/CommercialInfrastructure.swift)
for Keychain stores, [`PortsideBackendClient.swift`](../apps/desktop/Sources/PortsideCore/PortsideBackendClient.swift)
for client protocol checks, and [BACKEND](BACKEND.md) for API contracts and the
concurrency/deactivation limits. This is a commercial entitlement mechanism,
not an unbreakable boundary against a modified local app. Manifest and artifact
endpoints currently remain public; revocation cannot instantly invalidate an
offline client before its stored grace period expires.

## Configuration names and ownership

| Owner                         | Names read by current code                                                                                           |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Landing server checkout       | `STRIPE_SECRET_KEY`, fallback `STRIPE_TEST_API_KEY`, `STRIPE_PRICE_ID`, `APP_BASE_URL`                               |
| Landing server pricing        | `PORTSIDE_PRICE_AMOUNT`, `PORTSIDE_PRICE_CURRENCY`, `PORTSIDE_PRICE_LOCALE`                                          |
| Backend license service       | `LICENSE_HMAC_SECRET`, `LICENSE_SIGNING_PRIVATE_KEY_PEM`, `LICENSE_SIGNING_PUBLIC_KEY_PEM`, `LICENSE_SIGNING_KEY_ID` |
| Desktop release configuration | `PORTSIDE_LICENSE_PUBLIC_KEY`, `PORTSIDE_LICENSE_KEY_ID`                                                             |

The historical brief also names `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`,
`PORTSIDE_DOWNLOAD_BASE_URL`, and `EMAIL_PROVIDER_API_KEY`. Current landing and
backend code do not consume them. They are proposed integration configuration,
not proof that webhook verification or delivery exists. Keep license signing
private keys in backend secret storage and Stripe secrets in the landing server;
only public verification keys may enter the app bundle.

## Required evidence before a commercial claim

For future fulfillment work, validate Stripe test-mode success and failure,
invalid/replayed webhook rejection, stable idempotency, purchase/license
association, authenticated time-limited delivery, missing-payment behavior,
license activation/transfer/revocation, offline expiry, email delivery/resend,
and privacy of logs and browser bundles. Use a real database for concurrency
and challenge/deactivation race tests. The current landing has no test script;
backend unit mocks do not establish these integrations. Record commands and
results in [TESTING](TESTING.md) and [STATUS](STATUS.md).

Preserve the prior commercial checklist: verify exact Wine/bundled-library
license and corresponding-source requirements, wrapper/winetricks notices and
authorization, Sparkle/Sentry notices, and the inventory for each shipped
artifact. Steam must remain obtained from Valve, outside Portside's bundles and
storage. Provenance lives in [upstream/lock.json](../upstream/lock.json),
[UPSTREAM_VERSIONS.json](../UPSTREAM_VERSIONS.json), and the notices linked above;
[SIKARUGIR_AUTHORIZATION](../SIKARUGIR_AUTHORIZATION.md) records the authorization
boundary. This checklist records required review, not a grant of rights or a
verified approval.
