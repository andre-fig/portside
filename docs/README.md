# Documentation map

Read [root AGENTS.md](../AGENTS.md) first, then the task row below. Documentation
explains the code; it does not replace it. [STATUS](STATUS.md) records the audit
date, commit, actual checks and unverified operations.

## Canonical task references

The accepted runtime direction and missing source inputs are recorded in
[Sikarugir integration](SIKARUGIR_INTEGRATION.md) and the
[approved candidate adapter](SIKARUGIR_ADAPTER.md). The current direct-Wine
implementation must not be confused with a completed Sikarugir integration.

| Task                                                       | Read                                  | Purpose                                                              |
| ---------------------------------------------------------- | ------------------------------------- | -------------------------------------------------------------------- |
| Understand the system or locate entry points               | [ARCHITECTURE](ARCHITECTURE.md)       | Applications, bootstrap, data ownership and service relationships    |
| Change Wine, wrapper, host, Steam setup or runtime updates | [RUNTIME](RUNTIME.md)                 | Source/build boundaries, installation, migration and rollback limits |
| Change app updates, signing, publication or CI             | [RELEASE](RELEASE.md)                 | Workflow order, scripts, secret names and production-only operation  |
| Review trust, licensing or sensitive data                  | [SECURITY](SECURITY.md)               | Implemented controls and known gaps                                  |
| Select checks and interpret their evidence                 | [TESTING](TESTING.md)                 | Automated/manual test matrix and commands                            |
| Change an architectural boundary                           | [DECISIONS](DECISIONS.md)             | Confirmed decisions and superseded approaches                        |
| Assess progress or choose the next milestone               | [STATUS](STATUS.md)                   | Snapshot, blockers, risks and evidence                               |
| Set up a checkout                                          | [DEVELOPER_GUIDE](DEVELOPER_GUIDE.md) | Tools and local entry points                                         |
| Find a script/configuration owner                          | [PROJECT_GUIDE](PROJECT_GUIDE.md)     | Script and configuration catalog                                     |

Local instructions exist for [desktop](../apps/desktop/AGENTS.md),
[backend](../apps/backend/AGENTS.md), [runtime host](../apps/runtime-host/AGENTS.md),
[landing](../apps/landing/AGENTS.md), [runtime build scripts](../scripts/build-runtime/AGENTS.md)
and [GitHub automation](../.github/AGENTS.md).

## Specialized references and audit disposition

All repository-owned Markdown present at the audit base was reviewed; upstream
snapshot and generated dependency Markdown are excluded. No historical legal
notice was replaced with invented terms. The table records how older documents
fit the consolidated layer.

| Document                                                                                                                                        | Distinct purpose / disposition                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [Repository README](../README.md), [applications map](../apps/README.md)                                                                        | Short product and component entry points; updated links and component inventory                  |
| [CONTRIBUTING](../CONTRIBUTING.md), [Copilot router](../.github/copilot-instructions.md)                                                        | Contribution process and alternate agent entry point; duplicate rules now refer to AGENTS        |
| [Root ARCHITECTURE](../ARCHITECTURE.md)                                                                                                         | Compatibility link; obsolete compiled-upstream baseline removed from current guidance            |
| [DEVELOPMENT](DEVELOPMENT.md)                                                                                                                   | Compatibility link to DEVELOPER_GUIDE; duplicate setup consolidated                              |
| [RUNTIME_BUILD](RUNTIME_BUILD.md)                                                                                                               | Compatibility link to RUNTIME; build instructions consolidated                                   |
| [AUTOMATIC_UPDATES](AUTOMATIC_UPDATES.md), [UPDATE_ARCHITECTURE](UPDATE_ARCHITECTURE.md)                                                        | Update entry points to RELEASE/ARCHITECTURE; duplicated guarantees and secret lists consolidated |
| [ARTIFACT_SECURITY](ARTIFACT_SECURITY.md)                                                                                                       | Artifact trust entry point to SECURITY and backend contract                                      |
| [BACKEND](BACKEND.md)                                                                                                                           | API, data model, worker/cron and service limitations                                             |
| [RAILWAY_DEPLOYMENT](RAILWAY_DEPLOYMENT.md)                                                                                                     | Repository deployment configuration and external setup requirements, not a live report           |
| [LICENSING](LICENSING.md)                                                                                                                       | Purchase, activation and missing fulfillment integration                                         |
| [COMMERCIALIZATION](COMMERCIALIZATION.md)                                                                                                       | Release acceptance milestones; references canonical operational instructions                     |
| [VALIDATION](VALIDATION.md)                                                                                                                     | Manual clean-install/Steam/game acceptance protocol                                              |
| [BOOTSTRAP_VALIDATION](BOOTSTRAP_VALIDATION.md)                                                                                                 | Installation/update scenarios and explicitly historical local evidence                           |
| [STEAM_FIRST_LAUNCH_FIX](STEAM_FIRST_LAUNCH_FIX.md) | 0.1.28 SIGKILL reproduction, loader architecture controls, launch diagnostics and acceptance limits |
| [STEAM_GRAPHICS_FIX](STEAM_GRAPHICS_FIX.md) | 0.1.35 prefix upgrade, CEF/ANGLE loader controls, software rendering evidence and interactive acceptance limits |
| [ROLLBACK](ROLLBACK.md)                                                                                                                         | Operator checklist and boundaries; exact endpoint/script contract in RELEASE                     |
| [KEY_ROTATION](KEY_ROTATION.md)                                                                                                                 | Planned operator rotation procedure and implemented key-ring limits                              |
| [PRIVACY](PRIVACY.md)                                                                                                                           | Data ownership, diagnostics and incomplete retention controls                                    |
| [COMPATIBILITY_ENGINE](COMPATIBILITY_ENGINE.md), [GAME_PROFILES](GAME_PROFILES.md)                                                              | Scanner/profile contracts and unwired integration boundaries                                     |
| [RENDERERS](RENDERERS.md), [COMPATIBILITY_LIMITATIONS](COMPATIBILITY_LIMITATIONS.md)                                                            | Renderer inventory, fallback policy and actual execution limits                                  |
| [ANTICHEAT](ANTICHEAT.md), [UNturned_VALIDATION](UNturned_VALIDATION.md)                                                                        | Conservative anti-cheat policy and a code-level game fixture; no playability claim               |
| [UPSTREAM_MIRRORING](UPSTREAM_MIRRORING.md), [upstream README](../upstream/README.md)                                                           | Source synchronization and provenance-only snapshots                                             |
| [Runtime license procedure](../RUNTIME_LICENSES.md), [root LICENSING](../LICENSING.md)                                                          | Source/distribution responsibility; obsolete upstream binary wording corrected                   |
| [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES.md), [root notices](../THIRD_PARTY_NOTICES.md), [license inventory](../upstream/licenses/README.md) | Distinct legal inventories retained; locks own current revisions                                 |
| [SIKARUGIR_AUTHORIZATION](../SIKARUGIR_AUTHORIZATION.md)                                                                                        | Preserved project-supplied authorization statement; no signed grant inferred                     |
| [Runtime-host README](../apps/runtime-host/README.md)                                                                                           | Host/package entry point                                                                         |
| [Landing README](../apps/landing/README.md), [route README](../apps/landing/src/routes/README.md)                                               | Local site development and routing; obsolete starter material consolidated                       |

The audit found contradictory snapshots in earlier guides: two buckets vs one,
staging vs production-only, direct-DMG setup vs the installation gate, older
Sikarugir binaries vs Portside builds, and implementation vs graphical success.
Current contracts now live in the canonical documents. Useful historical
validation remains explicitly historical in BOOTSTRAP_VALIDATION and STATUS;
the original prose remains recoverable in Git history at the audited commit.
