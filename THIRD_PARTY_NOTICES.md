# Third-party notices

| Component | Version / revision | Source | Status |
|---|---|---|---|
| Swift, SwiftUI, Foundation, AppKit | macOS SDK | Apple SDK | Platform SDK; governed by Apple terms |
| Sentry Cocoa | 9.26.0+ | [getsentry/sentry-cocoa](https://github.com/getsentry/sentry-cocoa) | MIT; fetched by Swift Package Manager |
| Sparkle | 2.9.x | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) | Sparkle license and embedded notices; fetched by Swift Package Manager |
| Wrapper and native host | Portside source | `runtime/wrapper-template`, `apps/runtime-host` | Portside source; host is compiled during the runtime build |
| Wine source snapshot | commit `2df1ee28…` | `vendor/wine`; original repository is recorded in `upstream/lock.json` | LGPL-2.1-or-later and component notices |
| winetricks source snapshot | commit `5a59ea0…` | `vendor/winetricks`; original repository is recorded in `upstream/lock.json` | LGPL-2.1-or-later; packaged by Portside |
| Wrapper/engine metadata snapshots | pinned commits | `vendor/wrapper`, `vendor/engines` | Provenance and license review only; not executable build input |
| Creator | pinned provenance record | `upstream/lock.json` | Not imported; not required by the Portside build |
| Rosetta 2 | macOS-provided | Apple | Not bundled; installed only through Apple’s official mechanism |
| Steam for Windows | installed by steam verb | Valve official distribution | Not bundled; Valve terms and trademarks apply |
| DXMT, D3DMetal, DXVK, VKD3D | not enabled by baseline | official upstream mechanisms as selected later | Not installed during Steam baseline |
| Games, including GunZ: The Duel | none bundled | Steam | Not distributed by Portside |

Exact repositories, checksums, source commits, exclusions and local paths are
in `upstream/lock.json`. Upstream URLs are provenance only; production runtime
downloads come from Portside storage after signed-manifest promotion.
