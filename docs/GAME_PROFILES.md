# Game profiles

[CompatibilityEngine.swift](../apps/desktop/Sources/PortsideCore/CompatibilityEngine.swift)
defines `GameCompatibilityProfile`, keyed by Steam App ID, and separate
`ExecutableProfile` entries. Fields record architecture, detected APIs,
preferred/fallback renderers, overrides, environment/arguments, anti-cheat
evidence, source/confidence/version and prior outcomes.

The profile builder's candidate ordering is:

| Detected evidence        | Candidates             |
| ------------------------ | ---------------------- |
| D3D8 / D3D9              | WineD3D                |
| D3D10 / D3D11            | DXMT, WineD3D          |
| Unity with D3D10 / D3D11 | DXMT, DXVK, WineD3D    |
| D3D12                    | VKD3D, WineD3D         |
| Vulkan                   | Native Vulkan, WineD3D |
| OpenGL                   | Native OpenGL, WineD3D |
| No useful evidence       | WineD3D                |

These are selection rules, not validated capability claims. [RENDERERS](RENDERERS.md)
describes inventory and path limitations. Multiple executables can receive
different configurations; true isolation across arbitrary shared-prefix behavior
needs integration evidence.

The provider accepts an injected remote result only when its source tag is
`backendValidated`; this is a source-label check, not a signed profile protocol.
The normal Agent has no remote provider. Local validated/user-confirmed profiles,
PE analysis and conservative defaults provide the implemented offline path.
See [COMPATIBILITY_ENGINE](COMPATIBILITY_ENGINE.md).
