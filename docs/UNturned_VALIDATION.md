# Unturned Validation

Unturned is the general engine validation case for App ID `304930`; it is not a special compatibility exception and does not receive a hard-coded renderer rule.

The automated coverage validates:

- App ID and `libraryfolders.vdf`/`appmanifest_304930.acf` correlation;
- bounded PE evidence for Unity and D3D11;
- launcher and BattlEye evidence as separate profile signals;
- renderer candidates DXMT, DXVK and WineD3D;
- per-executable configuration and rollback without touching a save file;
- process results including graphics failure, anti-cheat unsupported and visual state unverified.

No BattlEye change or bypass is permitted. The official no-BattlEye launch option, if supplied by Steam/the game, remains an explicit user choice and is not invented by Portside.

This code-level validation does not claim that Unturned renders successfully. A real acceptance run must use the managed `PortsideBaseline.app`, then manually confirm the game window and usable rendered scene. Process existence, `steamwebhelper`, a Dock icon, a launcher window or a log line are insufficient.
