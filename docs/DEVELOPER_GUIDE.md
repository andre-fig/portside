# Developer guide

Read [root instructions](../AGENTS.md), [STATUS](STATUS.md) and the applicable
local `AGENTS.md` first. [ARCHITECTURE](ARCHITECTURE.md) maps application
boundaries; [PROJECT_GUIDE](PROJECT_GUIDE.md) maps scripts and configuration.

## Tools and setup

| Area                     | Repository tool contract                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------------- |
| Desktop and runtime host | macOS 13+, Swift tools 6.0 packages; supported runtime target is Apple silicon                           |
| Backend                  | Node 22 in Docker/CI, npm with committed package-lock                                                    |
| Landing                  | Bun 1.2.21 in local pre-push and Railway build, committed bun.lock                                      |
| Wine                     | Local macOS/Xcode build before engine-changing pushes, Homebrew compiler dependencies and AWS CLI for input handoff; record actual build versions |
| Source/policy checks     | POSIX shell, Git, ripgrep, jq; actionlint for workflows                                                  |

These are source configuration facts, not claims about tools installed on a
developer machine. Wine dependency versions/checksums are recorded but not all
enforced by the current Homebrew recipe; see [RUNTIME](RUNTIME.md).

From the repository root, install only dependencies needed for the task:

```sh
git rev-parse --show-toplevel
git status --short --branch
swift package resolve --package-path apps/desktop
(cd apps/backend && npm ci)
(cd apps/landing && bun install --frozen-lockfile)
```

There is no root install/test command. Optional `./scripts/install-git-hooks.sh`
changes `core.hooksPath` to the versioned hooks. Do not run it in an audit that
forbids configuration changes. Hook behavior and the complete check matrix are
in [TESTING](TESTING.md). Workflow edits require local `actionlint`; the hooks
check staged shell/JSON/Python/workflow syntax before commit and select both Swift
suites/builds, script regressions or web checks before push. Production trust
checks still run independently on Linux. Engine-changing pushes also prepare
and transfer the source-built engine locally; [RELEASE](RELEASE.md) lists the
required storage variable names. Keep their values in an approved secret provider,
not shell scripts, Git, logs or artifacts.

## Local application entry points

Desktop:

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/package_app.sh
```

The final command generates `build/Portside.app` and debug symbols. Opening
that app can access local Portside state and external services; use a dedicated
test account for bootstrap. Ad hoc development packaging is not a commercial
release. Commercial builds must install into `/Applications/Portside.app`
before bootstrap, including when launched from a DMG.

Backend, from `apps/backend`, after local configuration:

```sh
npm run prisma:validate
npm run dev
```

Use [.env.example](../apps/backend/.env.example) for variable names; never copy
production credentials. `npm run prisma:migrate:deploy` changes the selected
database and is only appropriate for an explicitly selected disposable/local
database during development. API, worker and cron are separate entry points in
[BACKEND](BACKEND.md); starting the worker can contact GitHub and mutate PostgreSQL.

Landing, from `apps/landing`:

```sh
bun run dev
```

This builds from the monorepo. No checkout of the former landing repository is
needed. Stripe checkout requires external configuration; a success redirect does
not establish payment or license delivery. See [LICENSING](LICENSING.md).

## Builds, diagnosis and completion

Use [TESTING](TESTING.md) for Swift, backend, landing, shell and manual checks;
[RUNTIME](RUNTIME.md) for Wine and runtime assembly; [RELEASE](RELEASE.md) for
bundle/DMG, signing, notarization and publication commands. Read each script
before invoking it: build directories are generated and some runbooks write to
external systems. Routine local development is not authorization to publish.

For a runtime failure, identify the selected signed manifest, component
versions, source/build evidence, download host and checksum result. Then inspect
sanitized staging/installation logs and managed process ownership. Confirm GUI
separately under [VALIDATION](VALIDATION.md); never kill all Wine or Steam processes.

Record commands and results in the change report. Update architecture docs
with code, STATUS for milestones and DECISIONS for changed boundaries.
Former operational reports in this guide were consolidated into the dated
[STATUS](STATUS.md) snapshot; no current release version is inferred from defaults.
