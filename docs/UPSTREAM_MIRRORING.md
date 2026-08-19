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

Rebuild from the repository alone with:

```sh
./scripts/build-runtime/build.sh
```

The current pinned Wrapper and Engines snapshots stop this command after
producing the local winetricks source artifact and provenance evidence. They
contain no wrapper/template source or engine build recipe/patch set. This is a
deliberate recorded blocker: the workflow never substitutes a downloaded
official binary. Wine and winetricks are present as source snapshots; the
engine-equivalent and wrapper build remain pending the missing inputs.

A missing external repository must not prevent a stable reinstall, repair,
rollback or use of an already installed runtime. The private bucket and
secondary replica are the production sources; upstream access is only for
future source synchronization. A Portside artifact needs a successful source
build, provenance, validation and explicit promotion before it can enter the
production manifest.
