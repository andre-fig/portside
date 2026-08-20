# Runtime licenses and source procedure

Portside does not place runtime binaries in its application bundle. The
source snapshots used for Portside builds live under `vendor/` and are
recorded in `upstream/lock.json`. A future runtime installation will download
only Portside-produced, signed artifacts from the Portside manifest and store
them under the user’s Portside directory.

The selected engine contains Wine and other upstream libraries. Their notices
must be preserved with the installed wrapper and surfaced in the diagnostic
export without credentials or account data. The primary source repositories,
exact clone commits, snapshot checksums and exclusions are listed in
`upstream/lock.json`.

For a source audit:

1. Validate the checked-in snapshots with `scripts/upstream/validate_snapshot.sh`.
2. Build only from `vendor/` and record the source commits in provenance.
3. Inspect the generated artifact’s notices and licenses before promotion.
4. Keep the public Portside source, this notice, upstream notices and the
   authorization record together.

The Portside wrapper template and native host are source-controlled in
`runtime/wrapper-template` and `apps/runtime-host`. The engine recipe builds
from `vendor/wine`; it must stop when a required native dependency is missing
and must never substitute a prebuilt third-party engine silently. Current
build validation status is recorded in `docs/RUNTIME_BUILD.md` and in the
generated provenance evidence.

No Portside change claims affiliation with Apple or Valve. Upstream provenance
and license obligations remain documented separately from the Portside product
interface.
