# Portside Compatibility Engine

The compatibility engine is a read-mostly, per-game layer over the existing official Steam bootstrap. It does not replace the bootstrap, copy a native macOS Steam session, or change the Portside baseline wrapper configuration.

## Flow

1. `SteamLibraryScanner` finds only libraries below Portside-managed roots and safely parses Valve KeyValues.
2. Completed manifests are correlated with a game directory and bounded executable scan.
3. `PEImportScanner` reads PE headers and import tables without executing a file. Engine, launcher and anti-cheat strings are evidence only.
4. `CompatibilityProfileProvider` resolves profiles in this order: validated backend profile, locally validated profile, PE analysis, conservative default.
5. `RendererManager` verifies an already installed official runtime component and applies Wine AppDefaults for one executable. It does not replace DLLs globally or edit game files.
6. `GameLaunchMonitor` records technical process outcomes. A graphical window or a stable process is never treated as visual success without confirmation.
7. `PortsideAgent` performs low-frequency scans and stops as soon as the managed Steam process tree is gone.

The agent uses direct `Process` specifications when it must invoke Wine or existing system probes. It does not use a shell, shell strings, account data, screen capture or input injection.

## Managed data

Profiles and lightweight attempts are stored below Portside's application-support root. They contain App IDs, executable paths, renderer choices and technical signals. Credentials, cookies, tokens, Steam IDs and personal account files are excluded and logs pass through the existing sanitizer.

## Current baseline inventory

The active `PortsideBaseline.app` was inspected on this Mac by filesystem and `Info.plist`, not by documentation:

- runtime: `WS12WineSikarugir10.0_6`, Wine `10.0 (revision 6)`;
- WineD3D: present for i386 and x86_64;
- DXMT and DXVK payloads: present;
- MoltenVKCX/MoltenVK: present and the wrapper flag is enabled;
- Wine GStreamer, Wine Mono `9.4.0` and Wine Gecko `2.47.4`: present;
- VKD3D: not found in the active wrapper;
- D3DMetal payload: physically present in the upstream wrapper package but disabled by `D3DMETAL=0` and excluded from the commercial renderer enum;
- MSYNC and ESYNC: both enabled; standard WineD3D baseline has `DXMT=0`, `DXVK=0`.

The runtime metadata currently reports GStreamer as not installed even though the active wrapper contains GStreamer files; this discrepancy is retained as diagnostic evidence rather than silently corrected.

`PortsideAgent --capture-diagnostics` writes a sanitized JSON snapshot under Portside Diagnostics with the wrapper options, environment, renderer inventory, component checksums, prefix structure, managed process sequence, Steam launch path/arguments and bounded installation/readiness/compatibility logs.
