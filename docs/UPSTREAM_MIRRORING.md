# Authorized upstream synchronization

[upstream/lock.json](../upstream/lock.json) owns source repository, full commit,
license/checksum, exclusions and submodule/LFS metadata.
[UPSTREAM_VERSIONS.json](../UPSTREAM_VERSIONS.json) is only a compatibility pointer.
Snapshots are source/provenance input, not Portside runtime documentation.

[Sync Upstreams](../.github/workflows/sync-upstreams.yml) runs daily at 03:17 UTC
or by dispatch and maintains a review PR. It invokes
[sync.sh](../scripts/upstream/sync.sh), which clones authorized sources into a
temporary area, stages changed snapshots, validates their layout, computes
source/license checksums and then replaces managed snapshots and the lock.
License changes are flagged, not automatically legally approved.

A source-download/staging failure occurs before the replacement loop.
The final multi-directory moves are not a filesystem transaction; inspect
partial changes on a move failure. The workflow can commit/push its branch
and manage obsolete PRs, but does not merge or publish runtime releases.
Running sync is a source mutation with network access, not a documentation audit.

The Wine and winetricks snapshots are executable build inputs; metadata-only
Wrapper/Engines snapshots and Creator provenance do not establish the source
for old compiled releases. Do not label those releases as Portside builds.
See [upstream README](../upstream/README.md) and [RUNTIME](RUNTIME.md).

For local integrity checks, use
[validate_snapshot.sh](../scripts/upstream/validate_snapshot.sh),
[snapshot_checksum.sh](../scripts/upstream/snapshot_checksum.sh) and
[license_inventory_checksum.sh](../scripts/upstream/license_inventory_checksum.sh).
The audit compared six source digests successfully; see [STATUS](STATUS.md).
Legal review remains separate under [RUNTIME_LICENSES](../RUNTIME_LICENSES.md)
and [SIKARUGIR_AUTHORIZATION](../SIKARUGIR_AUTHORIZATION.md).

Source changes do not authorize promotion. Engine/assembly workflow behavior
and the actual production-only publication boundary are in [RELEASE](RELEASE.md).
Installed-runtime recovery should use approved Portside artifacts, not live
upstream binary downloads.
