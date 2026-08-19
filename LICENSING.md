# Licensing and authorization

## Portside

Portside-owned code remains in this public repository. Its final distribution
license must be chosen by the project owner before a commercial release.

## Sikarugir and included components

Portside downloads official Sikarugir artifacts at runtime instead of
embedding Creator, Configure, Launcher or an engine in Portside.app. The
selected Wine sources are LGPL-2.1-or-later; the complete obligations for
Wine, winetricks and bundled libraries must be reviewed from the installed
artifact notices before redistribution.

The exact artifact provenance is recorded in UPSTREAM_VERSIONS.json, and the
user-visible authorization statement is kept separately in
SIKARUGIR_AUTHORIZATION.md. That statement records the information supplied in
the project request; it does not invent a contract, grant, trademark
permission or license text that was not provided.

## Steam and games

Portside does not include Steam or games and is not affiliated with or
endorsed by Valve Corporation. Steam is installed by the official Sikarugir
winetricks verb inside the user’s isolated wrapper. Portside never requests,
copies or reports account credentials, cookies, tokens or Steam IDs.

## Release gate

Before redistribution, obtain legal review for the selected Sikarugir
artifacts, source notices, update mechanism, code signing, Valve terms,
macOS privacy disclosures and the final Portside license.

The commercial licensing checklist is maintained in docs/LICENSING.md and
must be completed separately for each production runtime promotion.
