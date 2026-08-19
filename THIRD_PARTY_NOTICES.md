# Third-party notices

| Component | Version / revision | Source | Status |
|---|---|---|---|
| Swift, SwiftUI, Foundation, AppKit | macOS SDK | Apple SDK | Platform SDK; governed by Apple terms |
| Sentry Cocoa | 9.26.0+ | [getsentry/sentry-cocoa](https://github.com/getsentry/sentry-cocoa) | MIT; fetched by Swift Package Manager |
| Sparkle | 2.9.x | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) | Sparkle license and embedded notices; fetched by Swift Package Manager |
| Sikarugir Creator | 1.0.1 | Official repository recorded in `upstream/lock.json` | Provenance only; not copied into Portside |
| Wrapper source snapshot | commit `9f0e08d7…` | `vendor/wrapper` | Source snapshot contains no template build source; blocked |
| Engines source snapshot | commit `9581b3a7…` | `vendor/engines` | Source snapshot contains no engine build source; blocked |
| Sikarugir Wine source | commit `2df1ee28…` | `vendor/wine` | Source snapshot preserved; engine-equivalence build not validated |
| Sikarugir winetricks | commit `5a59ea0…` | `vendor/winetricks` | Source snapshot preserved; Portside source artifact build is available |
| WineD3D | included by selected engine | [official Wine source](https://github.com/Sikarugir-App/wine) | LGPL-2.1-or-later and component notices |
| Rosetta 2 | macOS-provided | Apple | Not bundled; installed only through Apple’s official mechanism |
| Steam for Windows | installed by steam verb | Valve official distribution | Not bundled; Valve terms and trademarks apply |
| DXMT, D3DMetal, DXVK, VKD3D | not enabled by baseline | official upstream mechanisms as selected later | Not installed during Steam baseline |
| Games, including GunZ: The Duel | none bundled | Steam | Not distributed by Portside |

Exact repositories, checksums, source commits, exclusions and local paths are
in `upstream/lock.json`. Upstream URLs are provenance only; production runtime
downloads come from Portside storage after signed-manifest promotion.
