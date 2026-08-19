# Anti-cheat Handling

The engine recognizes Easy Anti-Cheat, BattlEye, GameGuard, nProtect and other provider evidence from PE imports, bounded strings and process observations. Profiles record provider, possible kernel-driver requirement, Wine support status, native macOS availability, Portside status and evidence paths.

Anti-cheat handling is informational and conservative. Portside may identify an official bootstrap or repair path and record whether a provider is known to support the selected Wine environment. It never bypasses anti-cheat, changes a game binary, fakes a driver, injects code or disables a provider.

Anti-cheat evidence disables automatic renderer fallback. The user must be told when a game requires provider support that cannot be verified. An observed BattlEye launcher is not visual proof that the game is playable.
