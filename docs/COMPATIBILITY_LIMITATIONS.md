# Compatibility limitations

PE imports and bounded strings cannot establish every dynamically loaded API,
engine mode or launcher transition. Profiles can propose unavailable renderers;
payload detection is wrapper-specific. Current source builds use the baseline
in [RUNTIME](RUNTIME.md), not a formerly inspected upstream wrapper.

`GameLaunchMonitor.classify` in [PortsideAgent.swift](../apps/desktop/Sources/PortsideCore/PortsideAgent.swift)
requires both stability and `visualStateVerified` for `stable_launch`.
The current observer records `visualStateVerified: false`; stable process
existence therefore remains `visual_state_unverified`. A launcher or Steam
window does not prove a playable game scene.

[Fallback policy](RENDERERS.md) permits only a narrow offline graphics retry,
but end-to-end retry orchestration is not wired. Remote profile lookup is also
an extension point, not a live backend integration. Inventory/registry paths
still reference the old Wine directory; reconcile that mismatch before claiming
the current source-built renderer path works.

Former notes about an “active wrapper” with DXMT/DXVK/MoltenVKCX and absent
VKD3D were machine-specific historical observations. They are not current
repository evidence or a supported capability inventory.

Kernel anti-cheat, DRM, codecs, Windows-only services and proprietary launchers
remain compatibility constraints. Portside must not bypass them or modify a
game to fabricate support. See [ANTICHEAT](ANTICHEAT.md) and
[VALIDATION](VALIDATION.md) for the required evidence.
