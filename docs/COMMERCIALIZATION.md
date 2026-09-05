# Commercial readiness

Commercial readiness is an acceptance requirement, not a property inferred
from compiled code. [STATUS](STATUS.md) records current evidence. The runtime
and license protocol exist; payment fulfillment is incomplete and external
signing/storage/payment/deployment status was not checked during the audit.

Before a customer availability claim, obtain evidence for:

1. Source/distribution obligations in [LICENSING](../LICENSING.md), including
   exact runtime/component notices and corresponding sources.
2. A specific source-built runtime: signed manifest, matching hashes/sizes,
   provenance/SBOM and actual clean Steam/game acceptance.
3. The final app and DMG: Developer ID, Hardened Runtime, accepted notarization,
   staple, bundle validation and installation into Applications.
4. Actual manifest discovery, complete private-storage redirects, appcast
   archive signatures, Sparkle update/relaunch and recovery/data preservation.
5. Stripe payment confirmation, idempotent fulfillment, delivered license,
   activation/offline/revocation behavior, email and privacy/support operations.
6. Registered backend source/build/release records bound to the actual artifacts.

Use [RELEASE](RELEASE.md) for the real script sequence and configuration names;
[TESTING](TESTING.md) and [VALIDATION](VALIDATION.md) define acceptance.
The current production-only automatic workflow does not enforce all these
requirements. Do not invent a staging promotion or treat a workflow run as
authority to publish independently. The main app includes Sparkle/Sentry
dependencies; Wine/Steam remain outside its bundle.
