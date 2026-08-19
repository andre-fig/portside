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

The initial source audit is blocked for the Wrapper template and Sikarugir
engine: the pinned upstream repositories contain no buildable source for those
components. Portside does not substitute the old official binaries silently.

No Portside change modifies upstream binaries or claims affiliation with
Sikarugir, Apple or Valve.
