# Source licensing and authorization

Portside-owned source is tracked in this repository; no root distribution
license grant is present at the audit base. The project owner must establish
the applicable distribution terms before making a commercial rights claim.

## Runtime sources

Portside produces its own runtime artifacts from the wrapper/host source and
locked Wine/winetricks snapshots. It does not download precompiled Sikarugir
releases as a commercial fallback. Exact repositories, revisions and recorded
licenses are in [upstream/lock.json](upstream/lock.json); the compatibility
[UPSTREAM_VERSIONS](UPSTREAM_VERSIONS.json) file points there.

Preserve notices and corresponding-source obligations for every redistributed
component and transitive library. [RUNTIME_LICENSES](RUNTIME_LICENSES.md) and
[the third-party inventory](docs/THIRD_PARTY_LICENSES.md) define review inputs;
they do not establish legal approval of a particular release.

[SIKARUGIR_AUTHORIZATION](SIKARUGIR_AUTHORIZATION.md) preserves the project-supplied
authorization statement, including the public-source condition. It does not
supply a signed contract or expand trademark/license rights.

## Steam and commercial entitlement

Steam is obtained from Valve through the vendored winetricks verb, outside
Portside distribution. No games or native Steam account sessions are bundled.
Portside does not claim affiliation or endorsement by Valve or Apple.

[docs/LICENSING](docs/LICENSING.md) describes commercial purchase/activation and
missing fulfillment. Commercial entitlement and source-distribution licensing
are separate topics. Required license/notices review is not proof that either
checkout or a customer release currently works.
