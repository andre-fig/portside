# Game Profiles

`GameCompatibilityProfile` is keyed by Steam App ID and contains the game name, every discovered executable, architecture, detected graphics APIs, preferred and fallback renderers, DLL overrides, environment, arguments, anti-cheat evidence, profile version, source, confidence and last success/failure.

`ExecutableProfile` is intentionally separate from the game profile. Two executables from the same game can therefore use different renderer settings in the same Wine prefix. When shared-prefix registry state is unsafe, the later isolation implementation must use a per-game prefix rather than modifying global DLLs.

## Evidence rules

- D3D8 and D3D9 default to WineD3D.
- D3D10/D3D11 default to DXMT then WineD3D unless a validated profile says otherwise.
- Unity D3D11 may try DXMT, DXVK, then WineD3D.
- D3D12 proposes VKD3D followed by WineD3D, but VKD3D is rejected at runtime if the component is not actually present.
- Vulkan and OpenGL select their corresponding native bridge when verified, then WineD3D.
- PE imports, file names and strings are evidence, not proof of engine behavior. Multiple executables are scanned because launchers and game binaries frequently use different APIs.

The default profile is conservative and offline-capable. A backend profile is accepted only when marked validated; no account credentials are needed to resolve a local profile.
