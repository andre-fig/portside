# Unturned validation fixture

App ID `304930` is a general compatibility fixture, not a hard-coded game
exception. [PortsideCoreTests.swift](../apps/desktop/Tests/PortsideCoreTests/PortsideCoreTests.swift)
contains synthetic Valve manifest/library correlation, Unity/D3D11 PE evidence,
renderer configuration isolation/rollback and anti-cheat/outcome tests.

Those tests establish code behavior only when executed; they were not rerun
during this documentation audit. Renderer candidates include DXMT/DXVK/WineD3D,
but [current renderer limitations](RENDERERS.md) still apply.

No BattlEye bypass or game modification is permitted. An official alternative
launch mode, if actually supplied by the game, remains an explicit user choice.
Real acceptance needs the exact Portside runtime, a rendered game window and
a usable scene under [VALIDATION](VALIDATION.md). Processes, a Dock icon,
Steam/launcher windows or fixture success cannot establish playability.
