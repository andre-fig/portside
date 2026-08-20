# Authorized upstream mirroring

The canonical inventory is `upstream/lock.json`; `UPSTREAM_VERSIONS.json` is a
compatibility pointer. The `vendor/` tree contains source snapshots without
nested Git repositories. Each record preserves the exact commit, commit date,
license statement, submodule/LFS state, exclusions and deterministic snapshot
checksum.

`.github/workflows/sync-upstreams.yml` runs daily or manually. It invokes
`scripts/upstream/sync.sh`, which stages a shallow clone in a temporary
directory, resolves the remote commit, checks submodules/LFS, validates the
source tree, preserves notices and opens a pull request. The workflow never
merges or publishes automatically. If an upstream disappears, the workflow
fails before replacing the existing snapshot.

The Creator application remains provenance-only and the upstream launcher is
not copied into Portside. The repository does not mirror Valve's Steam
installer.

The original authorization record is `SIKARUGIR_AUTHORIZATION.md`; attach the
authoritative signed authorization document during legal review and update
that record before commercial distribution. `upstream/licenses/` is only an
inventory pointer: exact notices remain beside their source in each
`vendor/` snapshot.

Rebuild the Portside runtime from the repository sources with:

```sh
PORTSIDE_RUNTIME_VERSION=0.1.0 \
PORTSIDE_RUNTIME_ARTIFACT_URL_PREFIX=https://artifacts.example.invalid/staging/runtime/ \
./scripts/build-runtime/build.sh
```

The command builds the Portside wrapper/template, the native runtime host, a
Wine engine from `vendor/wine`, and a winetricks source archive. The pinned
Wrapper and Engines snapshots are retained as provenance only because they do
not contain executable build source. The workflow never substitutes a
downloaded compiled runtime when the source build fails.

The exact host dependencies are recorded in `upstream/dependencies.json`.
`docs/RUNTIME_BUILD.md` records the current validation result, architecture,
toolchain and any missing dependency. A successful build creates unsigned
staging evidence; signing, upload, promotion and production publication are
separate explicit steps.

A missing external repository must not prevent a stable reinstall, repair,
rollback or use of an already installed runtime. The private bucket and
secondary replica are the production sources; upstream access is only for
future source synchronization. A Portside artifact needs a successful source
build, provenance, validation and explicit promotion before it can enter the
production manifest.
