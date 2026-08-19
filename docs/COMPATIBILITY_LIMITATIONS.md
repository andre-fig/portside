# Compatibility Limitations

PE imports do not reveal every dynamically loaded graphics API, launcher transition or engine mode. A profile can therefore be wrong even when the scan is technically correct. Renderer availability is also wrapper-specific and is checked from the filesystem each time; a renderer proposed by a profile may be rejected when its payload or checksum is absent.

The agent observes only processes owned by the Portside wrapper/prefix. It does not inspect native macOS Steam, unrelated Wine prefixes or external processes. It runs at a low frequency and exits with managed Steam, so it is not a permanent Dock application or a CPU polling loop.

`stable_launch` means that the process remained alive for the configured observation window; it does not mean that a game window was visible or that a scene rendered. The category `visual_state_unverified` remains until a human confirms the graphical result.

Automatic fallback is intentionally limited to one offline retry after a clear graphics initialization or shader failure. No fallback is automatic for anti-cheat, launcher, Steam API, AssetBundle, missing non-graphics dependencies, crashes without evidence, stable launches or risk/online sessions.

The current active wrapper has no VKD3D payload. D3DMetal is excluded even though an upstream payload is physically present. These facts must be reported rather than hidden behind a simulated capability.

The engine does not promise compatibility with kernel anti-cheat drivers, DRM, undocumented launchers, proprietary codecs or games that require native Windows services. Such cases are reported with evidence and stopped without modifying the game.
