# Runtime build instructions

Read the [root instructions](../../AGENTS.md), [runtime contract](../../docs/RUNTIME.md),
[release contract](../../docs/RELEASE.md) and [current status](../../docs/STATUS.md)
before editing. Verify those descriptions against the scripts and lockfiles.

This directory builds Portside runtime components from controlled source inputs.
`build-engine.sh`/`build-wine-engine.sh` compile Wine; `resolve-engine.sh` names the
persistent component; `fetch-engine.sh` validates and reuses it; `build.sh`
assembles wrapper, engine and winetricks. `build-wrapper.sh` compiles
`apps/runtime-host`; `build-winetricks.sh` packages the vendored tool.
`changed-components.sh` works with workflow path filters to select builds.
`prepare-engine-push.py` builds the exact outgoing committed engine locally;
`engine-input.py` transfers unpublished inputs and performs native CI checks.
Hosted engine jobs must not fall back to compiling Wine when input is missing.

- Preserve local changes and all user prefixes, Steam installations, games,
  libraries, credentials and installed runtimes. Restrict cleanup to disposable
  build output whose ownership and path have been checked.
- Keep compiled Sikarugir artifacts out of commercial input. Legitimate upstream
  source URLs remain provenance, not a binary fallback. Never compile Wine in
  ordinary runtime assembly to hide a missing persistent engine.
- Do not manually edit `vendor/` snapshots. Use the authorized sync process or
  document patches in `upstream/patches/`; verify that a patch is actually applied
  by the recipe. Do not weaken checksums, source binding, manifest or layout checks.
- Preserve Steam's Valve download through the `steam` verb and the WineD3D
  baseline. Keep user-facing host output in English.
- Keep private keys outside checkout/bundles. Log only sanitized provenance,
  version and validation outcomes, never secrets or account data.
- Current channel is production only. Do not invent staging, mix environments,
  publish, promote or dispatch a workflow without explicit task authorization.

For source/build-script edits, run:

```sh
./scripts/build-runtime/source-audit.sh
./scripts/upstream/validate_snapshot.sh vendor/wine
./scripts/upstream/validate_snapshot.sh vendor/winetricks
jq -e . upstream/lock.json >/dev/null
jq -e . upstream/dependencies.json >/dev/null
for script in scripts/build-runtime/*.sh scripts/upstream/*.sh; do sh -n "$script"; done
./scripts/validate-production-policy.sh
git diff --check
```

Use [RUNTIME.md](../../docs/RUNTIME.md) for the engine/assembly commands and
[TESTING.md](../../docs/TESTING.md) for generated-layout, host and GUI acceptance.
A real runtime change needs a macOS build with recorded toolchain, layout and
manifest results when that environment is available. Report missing storage,
certificates or graphical session explicitly; do not execute publication as a
test. Documentation-only tasks need no Wine build.

Known traps: dependency JSON is not enforced by Homebrew installation; engine
keys omit toolchain/patch identity; engine upload is not a conditional immutable
write; manifest shell validation is structural; the clean-install script deletes
its configured root and needs an interactive terminal. Read the documented limits
before claiming reproducibility, safe rollback, signature or GUI success.

Generated material includes `build/`, `.cache/portside-wine`, Swift `.build/`,
archives, work/stage trees, checksum outputs, manifests, SBOM and provenance.
Do not edit or commit generated output to fix a build. Completion means reviewed
source/lock/license effects, appropriate checks recorded with limitations, related
documentation updated, [STATUS.md](../../docs/STATUS.md) changed when a milestone
changes, and [DECISIONS.md](../../docs/DECISIONS.md) updated for architectural decisions.
