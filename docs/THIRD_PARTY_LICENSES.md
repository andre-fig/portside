# Third-party license inventory

This is an operational inventory, not legal advice. Keep the exact notices and
source corresponding to every production artifact in the private mirror and
ship required notices with Portside.

| Component                          | Source/version                           | Review                                          |
| ---------------------------------- | ---------------------------------------- | ----------------------------------------------- |
| Swift, SwiftUI, Foundation, AppKit | Apple SDK                                | Apple terms                                     |
| Sentry Cocoa                       | pinned Swift package                     | MIT and package notices                         |
| Sparkle 2                          | `sparkle-project/Sparkle`                | Sparkle license and embedded notices            |
| WineD3D/Wine                       | selected approved engine/source revision | LGPL-2.1-or-later and included notices          |
| winetricks                         | selected approved source revision        | LGPL-2.1-or-later                               |
| Wrapper/template and native host   | Portside source                          | `runtime/wrapper-template`, `apps/runtime-host` |
| Steam for Windows                  | Valve official distribution              | Valve terms; not bundled by Portside            |

Run a source/license inventory for every new version before promotion. The
sync workflow records a separate license/notice checksum and marks the update
for review in the generated pull request when it changes. Do not merge that PR
or mark an artifact production merely because its checksum is correct.

Use [the source lock](../upstream/lock.json) and
[Swift resolution](../apps/desktop/Package.resolved) for current revisions.
The build-generated SBOM lists the main runtime packages; verify transitive
coverage separately. See [RUNTIME_LICENSES](../RUNTIME_LICENSES.md) and
[STATUS](STATUS.md); a source notice is not release approval.
