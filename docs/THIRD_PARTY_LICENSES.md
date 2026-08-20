# Third-party license inventory

This is an operational inventory, not legal advice. Keep the exact notices and
source corresponding to every production artifact in the private mirror and
ship required notices with Portside.

| Component | Source/version | Review |
| --- | --- | --- |
| Swift, SwiftUI, Foundation, AppKit | Apple SDK | Apple terms |
| Sentry Cocoa | pinned Swift package | MIT and package notices |
| Sparkle 2 | `sparkle-project/Sparkle` | Sparkle license and embedded notices |
| WineD3D/Wine | selected approved engine/source revision | LGPL-2.1-or-later and included notices |
| winetricks | selected approved source revision | LGPL-2.1-or-later |
| Wrapper/template and native host | Portside source | `runtime/wrapper-template`, `apps/runtime-host` |
| Steam for Windows | Valve official distribution | Valve terms; not bundled by Portside |

Run a source/license inventory for every new version before promotion. The
sync workflow records a separate license/notice checksum and blocks replacement
when it changes until it is reviewed. Do not mark an artifact production merely
because its checksum is correct.
