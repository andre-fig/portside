# GitHub automation instructions

Read the [root instructions](../AGENTS.md), [RELEASE.md](../docs/RELEASE.md),
[TESTING.md](../docs/TESTING.md) and [STATUS.md](../docs/STATUS.md) before editing
workflow documentation or implementation. Read the called scripts, event filters,
job dependencies and checkout revisions; workflow names are not proof of behavior.

`workflows/` owns source CI, desktop/landing validation, separate engine/runtime
builds, upstream-sync PR automation, production releases and the Railway health
check. `copilot-instructions.md` routes the same repository rules for Copilot.

- Preserve existing worktree changes. Never run a workflow dispatch, commit,
  push, merge, deploy, release, artifact upload or promotion without explicit
  authorization in the current task. Do not add automatic promotion as an
  incidental change. Existing YAML automatically publishes under its configured
  triggers; documentation must describe this truth without granting agent authority.
- `production` is the only commercial channel/environment in current YAML.
  Local validation bundles are not staging. Do not mix configurations or invent
  staging/promotion commands; architectural changes require an explicit decision.
- Keep production-only controls, signature checks, provenance/SBOM and
  artifact-host restrictions. The owner-approved Sikarugir input set must remain
  checksum-pinned with accurate upstream provenance. Desktop downloads still use
  authenticated Portside artifacts; no unverified upstream fallback is allowed.
- Secrets belong to approved external stores and ephemeral runner files. Public
  keys may enter app/helper configuration; private keys must never enter the
  bundle, repository or uploaded build artifact. Do not print secret values.
- Keep source-sync review separate from publication. Sync may maintain a source
  PR; it must not merge or release it. Preserve user data on self-hosted runners.
- Prefer Linux for checks that do not require macOS. Preserve meaningful build
  filters/concurrency; app changes should not trigger an unnecessary Wine build.
- Keep Portside UI and authored operational documentation in English.

For workflow changes, inspect both YAML and scripts, then run:

```sh
actionlint .github/workflows/*.yml
for script in scripts/*.sh scripts/build-runtime/*.sh scripts/upstream/*.sh; do sh -n "$script"; done
./scripts/validate-production-policy.sh
git diff --check
```

Run `actionlint` when installed; report its absence rather than silently claiming
it passed. Run the affected component checks in [TESTING.md](../docs/TESTING.md)
when workflow changes affect its build contract. Documentation-only changes need
link/instruction consistency checks rather than dispatched workflows.

Known traps: successful CI currently means source policy plus backend schema/build,
not the full local test suite; Environment protection is external; retained GitHub
artifacts expire; a storage upload does not establish backend registration;
Railway deployment is provider-side and separate from GitHub CI; the clean-GUI
script cannot confirm acceptance without an interactive terminal. Signatures/notarization,
Sparkle, Steam windows and games require their own recorded validation.

GitHub artifacts, build trees, downloaded runtimes, dSYM, DMG and ZIP files are
generated evidence, not editable source. Completion means relevant static checks
and source review, a documented trigger/output/permission impact, recorded external
limitations, updated [RELEASE.md](../docs/RELEASE.md) for workflow contract changes,
[STATUS.md](../docs/STATUS.md) for milestones and [DECISIONS.md](../docs/DECISIONS.md)
for architectural changes. Never report unobserved service or GUI success.
