# Renderer Management

The supported renderer enum is limited to components Portside can verify:

- WineD3D
- DXMT
- DXVK
- VKD3D
- native Vulkan
- native OpenGL

D3DMetal/GPTK is not a Portside renderer option. If its payload is present inside an upstream wrapper, the inventory records that fact and the disabled wrapper setting, but the compatibility engine will not select or enable it.

`RuntimeComponentInventory` records filesystem path, detected version, representative checksum and availability. `RendererManager` verifies those records before configuration, emits per-executable Wine AppDefaults, persists a snapshot, and can roll back the snapshot. The manager never replaces a prefix-wide DLL, modifies original game files, or copies user save/cloud data.

The first automatic fallback is deliberately narrow: only a clear graphics initialization or shader compilation failure, only once, only offline, and only without anti-cheat evidence or a risk flag. The previous AppDefaults snapshot is restored before the next renderer is applied. Stable, non-graphics, anti-cheat and online cases do not trigger an automatic fallback.

Current active-wrapper result: WineD3D, DXMT, DXVK and MoltenVKCX are detected; VKD3D is unavailable. The baseline still starts with WineD3D and all alternative renderer flags disabled.
