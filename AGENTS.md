# Working on Portside

Portside is a native English-language macOS app intended to automate Sikarugir
installation, configuration and the official Windows Steam client. Its current
custom Wine wrapper does not complete that integration; see
[the integration boundary and blockers](docs/SIKARUGIR_INTEGRATION.md).
Steam comes from Valve through winetricks; Portside does not distribute Steam, games, saves or
DRM/anti-cheat bypasses.

## Start here

1. Run `git rev-parse --show-toplevel` and `git status --short --branch`.
   Preserve all existing changes; never reset or discard work to clean the tree.
2. Read the nearest applicable `AGENTS.md`, the task documents below and
   [STATUS](docs/STATUS.md). Check implementation before relying on documentation:
   status is a dated snapshot, not a live service report.
3. Use [the development guide](docs/DEVELOPER_GUIDE.md) for setup and
   [the documentation index](docs/README.md) for specialized runbooks.

| Task area                      | Required reading                                                                                                 |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| macOS app and bootstrap        | [ARCHITECTURE](docs/ARCHITECTURE.md), [RUNTIME](docs/RUNTIME.md), [desktop instructions](apps/desktop/AGENTS.md) |
| Wine, wrapper or winetricks    | [RUNTIME](docs/RUNTIME.md), [runtime build instructions](scripts/build-runtime/AGENTS.md)                        |
| Runtime host                   | [RUNTIME](docs/RUNTIME.md), [host instructions](apps/runtime-host/AGENTS.md)                                     |
| Sparkle or application updates | [RELEASE](docs/RELEASE.md), [BOOTSTRAP_VALIDATION](docs/BOOTSTRAP_VALIDATION.md)                                 |
| Backend or manifests           | [ARCHITECTURE](docs/ARCHITECTURE.md), [RELEASE](docs/RELEASE.md), [backend instructions](apps/backend/AGENTS.md) |
| Licensing or checkout          | [ARCHITECTURE](docs/ARCHITECTURE.md), [SECURITY](docs/SECURITY.md), [LICENSING](docs/LICENSING.md)               |
| Landing                        | [landing instructions](apps/landing/AGENTS.md), [landing README](apps/landing/README.md)                         |
| CI, signing or notarization    | [RELEASE](docs/RELEASE.md), [TESTING](docs/TESTING.md), [workflow instructions](.github/AGENTS.md)               |
| Current progress or blockers   | [STATUS](docs/STATUS.md)                                                                                         |
| Architectural changes          | [DECISIONS](docs/DECISIONS.md)                                                                                   |

## Repository and sources of truth

`apps/desktop` owns SwiftUI, core, agent and installer; `apps/runtime-host` owns
the wrapper executable; `apps/backend` owns API/worker/cron and Prisma;
`apps/landing` owns the public site and checkout. `runtime/wrapper-template`
contains Portside runtime defaults. `scripts` and `.github/workflows` implement
build/release operations. There is no root package manager or shared `packages/` tree.

Code, tests, package lockfiles, Prisma migrations and actual scripts/workflows
are implementation evidence. `upstream/lock.json` records source provenance;
`upstream/dependencies.json` records intended build dependencies. Neither vendor
READMEs nor generated artifacts define Portside behavior. Correct documentation
when code and prose disagree.

## Commands from the repository root

Install only what the task needs; see [TESTING](docs/TESTING.md) for prerequisites,
coverage and manual checks. Dependency installation/builds create generated output.

```sh
swift package resolve --package-path apps/desktop
(cd apps/backend && npm ci)
(cd apps/landing && bun install --frozen-lockfile)

swift test --package-path apps/desktop
swift build --package-path apps/desktop
swift test --package-path apps/runtime-host
swift build --package-path apps/runtime-host
(cd apps/backend && npm run prisma:validate && npm run typecheck && npm run lint && npm test && npm run build)
(cd apps/landing && bun run lint && bun run typecheck && bun run build)
./scripts/validate-production-policy.sh
git diff --check
```

Optional local hook setup: `./scripts/install-git-hooks.sh` changes Git hook
configuration. Hooks are targeted checks, not the entire validation matrix.
Runtime builds require the separate engine/assembly runbook in [RUNTIME](docs/RUNTIME.md).

## Non-negotiable boundaries

- Preserve prefixes, Steam credentials, native Steam, games, saves, libraries,
  installed runtimes and unrelated processes. Use new disposable fixtures for
  destructive scenarios; never clean an everyday account to simulate first run.
- The project owner approved restoring the original Sikarugir components on
  2026-09-08. Use the exact inputs pinned in `upstream/sikarugir-runtime.json`,
  preserve upstream producer identity and notices, and distinguish Portside
  assembly from source compilation. Keep authenticated Portside manifests and
  artifact checks; do not introduce unverified or silent download fallbacks.
  Valve Steam and Apple Rosetta remain legitimate external installation sources.
- Do not hand-edit `vendor/` snapshots; use synchronization or a documented
  Portside patch. Do not hand-edit generated `.build/`, `DerivedData/`,
  `node_modules/`, `dist/`, `build/`, `artifacts/`, landing `.output/` or
  `src/routeTree.gen.ts`. Preserve notices, checksums, provenance and SBOM.
- Never put private keys, credentials, tokens, cookies, account data or personal
  paths in bundles, Git, logs, fixtures or docs. Document variable/secret names
  only. Use external secret stores; the app embeds public verification keys only.
- Do not weaken signature, checksum, size, host, path, version or installation
  checks to make a build pass. Keep shell arguments structured and logs sanitized.
- Keep all Portside UI and new documentation in English. Existing landing
  language inconsistencies are tracked in STATUS, not permission to repeat them.
- Do not mix staging and production. Current code has production only; local
  development builds are not a staging channel. Do not invent a staging runbook.
- Agents must not automatically promote releases or publish manifests. Commit,
  push, merge, deploy, release, external writes and promotion require an explicit
  request authorizing that action. Existing workflow automation is described in
  RELEASE; it is not authorization for an agent to trigger it.

## Minimum completion

Review the diff, preserve unrelated changes, run applicable checks and record
commands/results and omissions. Never claim graphical Steam/game success from
files, processes or Dock icons; real rendered windows and interaction are required.
Name any dependency on a graphical session, certificate or external service.

Update relevant docs with code; update STATUS when a milestone changes and
DECISIONS when architecture is adopted or superseded. Use `Verified`,
`Implemented but not end-to-end validated`, `Planned`, `Blocked` or `Unknown`
with evidence and scope. A green build proves only its checks.
