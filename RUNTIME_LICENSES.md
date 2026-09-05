# Runtime licenses and corresponding sources

Source snapshots for Portside builds live under `vendor/`, with exact identities
in [upstream/lock.json](upstream/lock.json). Runtime binaries are separate from
the desktop app; [RUNTIME](docs/RUNTIME.md) describes the build and authenticated
download path. Source metadata does not prove installed artifacts or approval.

For each intended distribution:

1. Validate snapshot layout with [validate_snapshot.sh](scripts/upstream/validate_snapshot.sh)
   and compare the [snapshot digest](scripts/upstream/snapshot_checksum.sh) with the lock.
2. Produce artifacts from the approved sources and retain build provenance,
   component checksums, SBOM and corresponding sources/notices.
3. Inspect the actual artifact's transitive libraries and obligations. A
   three-package SBOM does not prove complete transitive-license coverage.
4. Preserve [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md), the
   [source license inventory](docs/THIRD_PARTY_LICENSES.md) and
   [authorization record](SIKARUGIR_AUTHORIZATION.md).

The wrapper/template and host are Portside source. Wine is built from the
tracked snapshot; missing inputs must fail rather than silently substitute a
third-party binary. Steam and Rosetta remain Valve/Apple distributions and are
not mirrored by Portside. Current build/release evidence is in [STATUS](docs/STATUS.md).
