# Authorized upstream mirroring

The local provenance inventory is `UPSTREAM_VERSIONS.json`. A production
mirror must preserve the exact repository history/tags/submodules/LFS/release
assets/checksums/licenses and the source revision used for every approved
artifact. It must also retain the corresponding source whenever a license
requires source availability.

The mirror worker is allowlist-based and records the origin, commit/tag,
license and verification result before an artifact can enter staging. It does
not copy the Creator application or the upstream launcher into Portside source
code. It also does not create a mirror of Valve's Steam installer absent
written authorization.

A missing external repository must not prevent a stable reinstall, repair,
rollback or use of an already installed runtime. The private bucket and the
secondary replica are the production sources; upstream access is only for
future discovery.
