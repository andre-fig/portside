# Audit status — 2026-09-05 UTC

This is a snapshot and can become stale. It is not a live deployment report.
Update it when a milestone changes, with commit, command/result and validation
scope; update [DECISIONS](DECISIONS.md) when architecture changes.

- **Audit date:** 2026-09-05 UTC; initial clock reading 01:51:44 UTC.
- **Audited commit:** `3eb02cca022eb8140fe29d11170213782a40f4c9`.
- **Before audit:** clean worktree, local branch `main`, status displayed
  `main...origin/main`. No fetch was performed; remote freshness is Unknown.
- **Scope:** repository-owned source/tests/docs/scripts/workflows/configuration and
  local Git history. Vendor source integrity was checked; generated dependencies,
  artifacts, installed applications and user data were not operational evidence.
- **Actions:** local documentation edits and non-destructive local checks only.
  No dependency installs/builds, GUI, credentials, service calls or publication.

## Installation follow-up — 2026-09-05 UTC

**Verified, scoped:** the [reopen correction](INSTALLATION_REOPEN_FIX.md) passed
116 desktop tests (one optional probe skipped), the desktop build and production
policy. A disposable copy of the authentic signed/notarized app passed the new
Gatekeeper/quarantine preparation and opened at its exact requested path without
translocation. This follow-up does not establish complete customer bootstrap or
Steam acceptance; the audit matrix below retains its original scope.

## Executive assessment

The repository implements the native application/install/update pipeline, a
Portside source-build runtime, commercial license protocol and API artifact
control plane. A clean customer journey is not established by this audit.
Checkout fulfillment is incomplete, runtime recovery/trust gaps remain, and
external deployment/signing/payment state was not queried.

The current system uses **production only**, **one artifact bucket**, and
**automatic qualifying releases after CI**. Staging-before-production and a
universally manual promotion pipeline are not the current implementation.
Future agents still require explicit task authorization for external publication.

## Operational evidence matrix

Definitions are in [TESTING](TESTING.md). “Not verified during this audit”
qualifies external/historical evidence; it is not a sixth operational state.

| Area                                              | Status                                   | Evidence                                                                                       | Missing validation                                                                     | Next action                                                                   |
| ------------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Source policy and snapshot identity               | Verified                                 | Production policy passes; six source snapshot digests match lock; source-presence audit passes | Does not prove compiler output, legal approval or reproducibility                      | Repeat when snapshots change                                                  |
| Shell/JSON/plist/workflow syntax                  | Verified                                 | 35 shell/hook files, 18 JSON/resolution files, five plists/entitlements; actionlint passes     | Script execution/remote job results                                                    | Run affected area tests for code changes                                      |
| Committed runtime manifests                       | Verified                                 | Both blocked empty fixtures fail production structural validator as expected                   | No authentic usable runtime manifest inspected                                         | Use approved signed release evidence for integration testing                  |
| App installation and bootstrap                    | Implemented but not end-to-end validated | Installer, bootstrap, preflight and test sources; historical partial report below              | Full commercial first launch, authorization denial, update/Steam sequence              | Dedicated account + signed candidate acceptance                               |
| Sparkle                                           | Implemented but not end-to-end validated | Coordinator, tests, appcast generation and release scripts                                     | Normal/critical install, relaunch and expected-version checks with two actual builds   | Authorize isolated fixture feed/builds; do not invent a staging service       |
| Developer ID / Hardened Runtime                   | Unknown                                  | Signing script; prior local candidate report                                                   | Current identities, final artifacts and verification                                   | Validate final signed artifacts in authorized environment                     |
| Notarization / staple / DMG                       | Unknown                                  | Notarization/DMG scripts; prior candidate report                                               | Current Apple result and final app/DMG tickets                                         | Verify exact final artifacts; ZIP contains stapled app                        |
| Wine engine build                                 | Implemented but not end-to-end validated | Recipe, lock, source digests, engine resolver                                                  | No fresh compiler run or Wine execution                                                | Build with recorded tools and preserve evidence                               |
| Runtime assembly                                  | Implemented but not end-to-end validated | Wrapper/host/winetricks assembly and persistent-engine fetch                                   | Current stored engine + complete artifact layout/build result                          | Fetch matching approved engine and assemble in authorized build area          |
| Runtime signed manifest delivery                  | Implemented but not end-to-end validated | Signer, backend publish verifier, client verifier, stable API redirect                         | Real signed discovery/download/checksum/install                                        | Trace one release across storage, DB and desktop                              |
| GitHub Actions execution / environment reviewers  | Unknown                                  | YAML and static lint only                                                                      | Current runs, secrets, approvals, branch protection                                    | Inspect externally only in an authorized operational task                     |
| Artifact publication / storage policy             | Unknown                                  | Single-bucket publishers and S3 client                                                         | Object existence/hash, public/private policy, retention and backups                    | Validate the configured bucket and final URLs                                 |
| Railway API/worker/PostgreSQL/landing             | Unknown                                  | Dockerfile, service JSON, worker and Railway connector                                         | Deployed revision, readiness, migrations, connector configuration                     | Verify provider configuration and exact running revision                      |
| Cron synchronization                              | Planned                                  | Cron entrypoint currently logs startup only                                                    | Actual periodic work                                                                   | Implement an explicit job if required                                         |
| Stripe payment / Apple Pay / DNS / email services | Unknown                                  | Checkout call and proposed configuration names                                                 | Live/test-mode payment/domain/provider evidence                                        | Use a separately authorized commerce validation                               |
| Checkout fulfillment                              | Blocked                                  | `getOrderStatus` always pending; no webhook/purchase writer/license issuer/email handler       | Complete paid purchase → delivered license                                             | Implement fulfillment with authenticated, idempotent payment processing       |
| Existing-license activation/refresh/offline use   | Implemented but not end-to-end validated | P-256 device proof, Ed25519 token, Keychain, backend tests                                     | Real DB concurrency, transfer/revocation and device flow                               | Dedicated license fixtures and integration tests                              |
| Clean runtime installation                        | Blocked                                  | Source-inferred nested prefix link in operator script; host/desktop fixtures exist             | Fix harness prefix identity, then authentic artifacts + test account + Valve/Apple/GUI | Follow [VALIDATION](VALIDATION.md) without cleaning user data                 |
| Steam rendered login / interaction / continuity   | Unknown                                  | Readiness code deliberately cannot prove visual success                                        | Real rendered interactive window and updater/close behavior                            | Human confirmation on a real Mac                                              |
| Game execution                                    | Unknown                                  | Compatibility source and Unturned fixture                                                      | Download, launch and usable rendered game scene                                        | Control-game acceptance; no universal compatibility claim                     |
| App/runtime rollback                              | Blocked                                  | Signed rules and recovery code exist, but target/selection defects below                       | Reliable previous-version recovery and data preservation                               | Resolve contract defects, then inject failures with disposable data           |
| Prefix, games and credential preservation         | Implemented but not end-to-end validated | External managed prefix/symlink design and fixtures                                            | Interrupted setup/update/repair/rollback with real layout                              | Validate synthetic markers and persistence without touching everyday accounts |
| Sentry delivery / privacy operations              | Unknown                                  | Sanitizer and SDK setup code; logging gaps below                                               | Live delivery, retention/deletion process and complete export audit                    | Review all producers and authorized service settings                          |
| English product language                          | Implemented but not end-to-end validated | Native metadata/new bootstrap strings; release metadata check                                  | Existing landing copy is Portuguese                                                    | Separate copy change; no production copy edited in this audit                 |

## Concrete risks and next milestones

1. **Runtime integrity and recovery:** pending local archives are not authenticated
   again at apply time; tar path checks do not explicitly validate link targets.
   The clean-install harness links into the template's existing prefix directory,
   apparently separating host state from its external Steam/marker checks; this is
   a source inference, not an executed failure. Wrapper replacement precedes final prefix/layout work; UUID lexical rollback
   selection and a literal failed-destination name make recovery unreliable.
   See [SECURITY](SECURITY.md) and [RUNTIME](RUNTIME.md).
2. **Release rollback contract:** backend rollback requires a published target even
   though newer publication supersedes it; an old signed payload does not create
   new downgrade authorization. Superseded appcast entries can fail download
   routes that require production records. See [RELEASE](RELEASE.md).
3. **Build/release evidence:** toolchain locks are descriptive, engine keys omit
   architecture/toolchain/patch identity, uploads have no enforced immutability,
   and the recipe does not apply the referenced patch directory. Current CI
   does not run Swift/backend unit suites; runtime registration records
   `cleanInstall: not_verified` and GUI acceptance is not a release gate.
4. **Compatibility wiring:** inventory/registry paths still reference
   `SharedSupport/wine` while the current runtime uses `SharedSupport/engine`.
   Remote profiles and automatic post-failure renderer retry are not wired
   end to end. Stored renderer rollback does not fully restore named registry
   overrides. Renderer candidates are not installed/working capabilities.
5. **Commerce and licensing:** implement fulfillment before claiming delivery;
   exercise concurrent one-device activation and challenge/deactivation races.
   Public artifact routes are not entitlement gates. See [LICENSING](LICENSING.md).
6. **Operational boundaries:** no live service result is available. The backend
   image omits dev dependencies while API predeploy calls the Prisma CLI declared
   there; actual CLI availability/migration needs evidence. A log-only cron is
   not reconciliation. Package app can optionally upload dSYM if Sentry is configured.
7. **Privacy:** main app logs have redaction/rotation, but runtime-host logs lack
   rotation, raw game-attempt JSON can hold paths, and backend/landing raw errors
   bypass some sanitizers. A stated privacy policy is not a retention job.
8. **Acceptance milestone:** after the above contracts are reviewed, validate a
   specific signed/notarized app with a specific authenticated runtime in a fresh
   account: install, update/relaunch, activate license, install Steam, interact,
   run a control game and recover while preserving data.

These are source findings and missing evidence, not demonstrated exploits or
permission to change code/infrastructure in this audit.

## Historical evidence retained, not reverified

| Original report                                                                            | What it recorded                                                                                                                                                               | How to interpret now                                                                                                          |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Former DEVELOPER_GUIDE, 2026-08-20                                                         | Runtime 0.1.6, build 32325605325-1, signed private-storage publication and a responding API                                                                                    | Historical report only; no current release, object or health inference. Original at audited commit in Git history             |
| [BOOTSTRAP_VALIDATION](BOOTSTRAP_VALIDATION.md), local 2026-09-04 / UTC 2026-09-05 session | 110 passing desktop tests plus a skipped probe, later information-only installed Sparkle probe, five host tests, signed/notarized candidate and fixture relocation/replacement | Self-reported prior-session evidence; generated logs, Apple receipts and installed artifacts were not inspected in this audit |
| Same bootstrap report                                                                      | Engine fetch stopped without storage configuration; no clean Steam/game test, no normal/critical update fixture, real admin prompt unproven                                    | Preserve these explicit limits; candidate signing does not establish customer rollout                                         |

The earlier report's candidate versions and ignored artifact locations remain
historical context. No current filesystem or service condition is asserted from them.

## Commands executed during this audit

| Command / local check                                                                                   | Result and scope                                                                                                    |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `git rev-parse --show-toplevel`, `git status --short --branch`, `git rev-parse HEAD`                    | Root confirmed; clean starting tree and commit recorded above                                                       |
| Local UTC clock                                                                                         | Audit started 2026-09-05 01:51:44 UTC                                                                               |
| `git ls-files`, `rg --files`, `rg -n`, `cat`, `sed`, `git log` and selected `git show`                  | Mapped owned Markdown, applications, tests, scripts, workflows/configuration and decision history; no fetch/network |
| `./scripts/validate-production-policy.sh`                                                               | Passed                                                                                                              |
| `./scripts/build-runtime/source-audit.sh`                                                               | Passed required-input presence                                                                                      |
| `./scripts/build-runtime/resolve-engine.sh`                                                             | Passed; derived `wine-Wineversion11.16-8da89f8493b2`; does not prove stored engine existence                        |
| `./scripts/build-runtime/validate-manifest.sh docs/runtime-manifest.json`                               | Exit 1 as expected: blocked, zero components, no signature                                                          |
| `./scripts/build-runtime/validate-manifest.sh apps/backend/manifests/runtime-manifest.json`             | Exit 1 as expected for the same blocked-fixture conditions                                                          |
| Local Python read-only checksum calculation matching snapshot_checksum.sh's path/content/link algorithm | All six snapshots match lock; 12,597 files, no symlinks; no vendor modifications                                    |
| `sh -n` via local file-list loop; Python JSON/plist parsing                                             | 35 shell/hook, 18 JSON/resolution, five plist/entitlement files passed                                              |
| `actionlint .github/workflows/*.yml`                                                                    | Passed; no workflow dispatch/execution                                                                              |
| Documentation formatter, link/source-reference and sensitive-pattern checks                             | Passed; see documentation validation below                                                                          |
| `git diff --check`, `git diff --stat`, final path/status inspection                                     | Passed; see documentation validation below                                                                          |

Full Swift/backend/landing suites, dependency installation, Wine/runtime build,
signing, notarization, clean-install, game, Sparkle install and rollback were not
executed. They would create excluded generated outputs or require GUI,
certificates, user data or external services. This task changed documentation only.

## Documentation validation

- Reviewed all 53 repository-owned Markdown files; 52 changed (12 new, 40 updated).
  The project-supplied Sikarugir authorization statement is preserved unchanged.
- Checked 664 relative links, including local anchor targets, with no missing
  targets. Checked 37 script-path spellings, 87 inline source references and
  seven named npm/Bun scripts against the checkout/package definitions.
  External URLs were not fetched.
- Used the already installed landing Prettier executable: the initial check
  identified formatting issues in 21 files; formatted only the explicit set of
  52 changed Markdown files. The final check passes. No formatter configuration
  or dependency was changed and no repository-wide write command was used.
- Personal-path/private-key/token/credential-URL pattern scans and manual review
  found no secrets or personal paths introduced in documentation.
- Root and six component AGENTS agree on preservation, English UI, generated
  inputs, production-only reality and explicit agent publication authority.
  Independent component reviews confirmed navigation from the root router to
  the applicable document, source entry point, invariant, test and status.
- `git diff --check` passes. Final path inspection contains only Markdown;
  `git diff --exit-code -- vendor` passes. No production code, workflow YAML,
  infrastructure/configuration, dependency, installed app or user data was changed.
  No file was written inside the excluded generated/snapshot directories.
- `git diff --stat` was reviewed for all 40 tracked edits; its normal output
  excludes the 12 new untracked documentation files, which were checked separately.
- No commit, push, merge, deploy, release, manifest promotion, service request
  or other external mutation occurred.

The index in docs/README.md records the disposition of every old document.
Useful historical validation is scoped to its original report; obsolete duplicate
recipes now route to canonical references. The largest staleness risks are future
bootstrap/release changes, service configuration, source locks and milestone
results; re-check their owners rather than treating this snapshot as live truth.
