# Commercial licensing checklist

Portside-owned code remains subject to the license selected by the project
owner. The commercial release must ship the applicable Portside notice plus
the exact third-party notices for every approved runtime artifact.

Before publishing, confirm:

- Wine and bundled libraries satisfy LGPL-2.1-or-later and source/notice
  obligations.
- winetricks, wrapper/template and engine authorization covers the exact
  production versions and redistribution/storage model.
- Sparkle 2 license and embedded notices are included.
- Steam is not bundled or mirrored by Portside and Valve terms/trademarks are
  respected.
- Sentry, Swift packages and all generated artifacts have an inventory entry.

The provenance and authorization records are in `UPSTREAM_VERSIONS.json`,
`RUNTIME_LICENSES.md`, `THIRD_PARTY_NOTICES.md` and
`SIKARUGIR_AUTHORIZATION.md`. This checklist is not a grant of rights; legal
review is required before a commercial release.
