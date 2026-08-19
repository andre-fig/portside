# Runtime licenses and source procedure

Portside does not place Sikarugir binaries in its application bundle. At
runtime it downloads the official Wrapper template, Engines artifact and
Sikarugir winetricks script, verifies their checksums, and stores them under
the user’s Portside directory.

The selected engine contains Wine and other upstream libraries. Their notices
must be preserved with the installed wrapper and surfaced in the diagnostic
export without credentials or account data. The primary source repositories
and exact clone commits are listed in UPSTREAM_VERSIONS.json.

For a source audit:

1. Clone the official repositories at the recorded commits.
2. Verify the downloaded artifact SHA-256 against docs/runtime-manifest.json.
3. Inspect the archive’s notices and licenses before redistribution.
4. Keep the public Portside source, this notice, upstream notices and the
   authorization record together.

No Portside change modifies upstream binaries or claims affiliation with
Sikarugir, Apple or Valve.
