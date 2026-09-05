# Third-party notices

| Component                          | Version / revision           | Source                                                                       | Status                                                                 |
| ---------------------------------- | ---------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Swift, SwiftUI, Foundation, AppKit | macOS SDK                    | Apple SDK                                                                    | Platform SDK; governed by Apple terms                                  |
| Sentry Cocoa                       | locked in Package.resolved   | [getsentry/sentry-cocoa](https://github.com/getsentry/sentry-cocoa)          | MIT; fetched by Swift Package Manager                                  |
| Sparkle                            | locked in Package.resolved   | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle)        | Sparkle license and embedded notices; fetched by Swift Package Manager |
| Wrapper and native host            | Portside source              | `runtime/wrapper-template`, `apps/runtime-host`                              | Portside source; host is compiled during the runtime build             |
| Wine source snapshot               | commit in upstream/lock.json | `vendor/wine`; original repository is recorded in `upstream/lock.json`       | LGPL-2.1-or-later and component notices                                |
| winetricks source snapshot         | commit in upstream/lock.json | `vendor/winetricks`; original repository is recorded in `upstream/lock.json` | LGPL-2.1-or-later; packaged by Portside                                |
| Wrapper/engine metadata snapshots  | pinned commits               | `vendor/wrapper`, `vendor/engines`                                           | Provenance and license review only; not executable build input         |
| Creator                            | pinned provenance record     | `upstream/lock.json`                                                         | Not imported; not required by the Portside build                       |
| Rosetta 2                          | macOS-provided               | Apple                                                                        | Not bundled; installed only through Apple’s official mechanism         |
| Steam for Windows                  | installed by steam verb      | Valve official distribution                                                  | Not bundled; Valve terms and trademarks apply                          |
| DXMT, D3DMetal, DXVK, VKD3D        | not enabled by baseline      | official upstream mechanisms as selected later                               | Not installed during Steam baseline                                    |
| Games, including GunZ: The Duel    | none bundled                 | Steam                                                                        | Not distributed by Portside                                            |

Exact repositories, checksums, source commits, exclusions and local paths are
in `upstream/lock.json`. Upstream URLs are provenance only; production runtime
downloads come from Portside storage under the signed-manifest verification contract.

Current exact Swift revisions are in [Package.resolved](apps/desktop/Package.resolved);
source identities are in [upstream/lock.json](upstream/lock.json). This inventory
is not a current operational or legal-approval report; see [STATUS](docs/STATUS.md).
