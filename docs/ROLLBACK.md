# Recovery and rollback checklist

Current rollback is **Blocked** from a reliable end-to-end claim by the gaps in
[RELEASE](RELEASE.md) and [RUNTIME](RUNTIME.md). This is an operator checklist,
not a promise that republishing an older version restores installed clients.

Before an explicitly authorized recovery:

1. Identify the current app/runtime manifest, source/build IDs, known usable
   target and exact signed artifacts. Retain both candidate and previous evidence.
2. Check the backend target's eligibility, client signed downgrade/minimum-app
   requirements and storage URL accessibility. Normal runtime publication
   supersedes the previous manifest, conflicting with rollback's published-target
   precondition; an old signature does not create new downgrade authorization.
3. For app recovery, use a signed/notarized fixed build with a version Sparkle
   accepts. Older appcast entries alone do not establish automatic downgrade;
   superseded enclosure download eligibility also needs validation.
4. For local runtime recovery, inspect staging/rollback selection and prefix
   state before replacement. Current rename-based helper has no crash journal
   and sorts UUID rollback directories lexicographically.
5. In a disposable account, inject failure and confirm the retained prefix,
   Steam installation, library, saves and license state remain intact. Then
   manually confirm rendered Steam interaction and the control game.

Administrative route and request fields are documented in [RELEASE](RELEASE.md)
and [BACKEND](BACKEND.md). Do not invoke them merely to test this documentation.
Never delete user prefixes, credentials, SteamLibrary or games during recovery.
Record actual outcome and missing validation in [STATUS](STATUS.md).
