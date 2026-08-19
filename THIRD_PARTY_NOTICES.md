# Third-party notices

| Component | Version | Source | License / redistribution status |
|---|---:|---|---|
| Apple Swift / SwiftUI / Foundation / AppKit | Xcode 26.2 SDK | Apple SDK | Platform SDK; governed by Apple terms, not bundled as a standalone dependency |
| Sentry Cocoa SDK | 9.26.0+ | [getsentry/sentry-cocoa](https://github.com/getsentry/sentry-cocoa) | MIT; fetched by Swift Package Manager |
| Wine Staging macOS build | 11.15 | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.15) | Wine LGPL-2.1-or-later; upstream packaging license is not declared in GitHub metadata; downloaded, not bundled |
| WineD3D | 11.15 | Included in Wine build | Wine LGPL-2.1-or-later; used for Direct3D 9/10/11 |
| GStreamer macOS runtime | 1.28.5 | [GStreamer official package](https://gstreamer.freedesktop.org/download/) | LGPL-2.1-or-later and component-specific licenses; downloaded, verified, and extracted locally |
| Rosetta 2 | macOS-provided | Apple | Not included; detected/installed through Apple’s official mechanism |
| Steam for Windows installer | downloaded at runtime | Valve official CDN | Not bundled; user obtains the official installer. Valve terms and trademarks apply |
| DXMT | not installed | 3Shain/dxmt | Upstream metadata reports no asserted license; excluded from this MVP |
| Games, including GunZ: The Duel (App ID 3139440) | none bundled | Steam | Not distributed by Portside |

This inventory must be updated with exact versions and license texts before adding a runtime or any other redistributable dependency.
