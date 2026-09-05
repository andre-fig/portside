# Anti-cheat boundary

[PEImportScanner and profile builder](../apps/desktop/Sources/PortsideCore/CompatibilityEngine.swift)
recognize provider evidence such as Easy Anti-Cheat, BattlEye, GameGuard and
nProtect from bounded file inspection. Profiles record provider, possible
kernel-driver requirement and support status; default Wine support is
`unknown`, not an externally verified compatibility database.

Anti-cheat evidence blocks the [automatic fallback policy](RENDERERS.md).
Portside must not patch game binaries, fake drivers, inject bypasses or disable
a provider to manufacture compatibility. An official game-supplied alternative
launch mode requires explicit user choice; Portside must not invent one.

Provider or launcher detection is not proof of a playable game. See
[UNturned_VALIDATION](UNturned_VALIDATION.md) for code fixtures and
[VALIDATION](VALIDATION.md) for separate rendered-scene acceptance.
