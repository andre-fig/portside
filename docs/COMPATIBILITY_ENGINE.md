# Portside Compatibility Engine

The compatibility engine is a read-mostly, per-game layer over the Portside
Steam runtime. It does not replace the bootstrap, copy a native macOS Steam
session, or change the Portside baseline wrapper configuration.

## Flow

1. `SteamLibraryScanner` finds only libraries below Portside-managed roots and safely parses Valve KeyValues.
2. Completed manifests are correlated with a game directory and bounded executable scan.
3. `PEImportScanner` reads PE headers and import tables without executing a file. Engine, launcher and anti-cheat strings are evidence only.
4. `CompatibilityProfileProvider` resolves profiles in this order: validated backend profile, locally validated profile, PE analysis, conservative default.
5. `RendererManager` verifies an already installed Portside runtime component and applies Wine AppDefaults for one executable. It does not replace DLLs globally or edit game files.
6. `GameLaunchMonitor` records technical process outcomes. A graphical window or a stable process is never treated as visual success without confirmation.
7. `PortsideAgent` performs low-frequency scans and stops as soon as the managed Steam process tree is gone.

The agent uses direct `Process` specifications when it must invoke Wine or existing system probes. It does not use a shell, shell strings, account data, screen capture or input injection.

## Managed data

Profiles and lightweight attempts are stored below Portside's application-support root. They contain App IDs, executable paths, renderer choices and technical signals. Credentials, cookies, tokens, Steam IDs and personal account files are excluded and logs pass through the existing sanitizer.

## Current baseline inventory

The intended baseline is the Portside-produced wrapper with WineD3D,
`D3DMETAL=0`, `DXMT=0`, `DXVK=0`, MSYNC and ESYNC enabled. The inventory is
populated only after the generated wrapper and engine pass the clean-layout and
real-display validation steps; source metadata alone is not treated as a
working runtime.

`PortsideAgent --capture-diagnostics` writes a sanitized JSON snapshot under Portside Diagnostics with the wrapper options, environment, renderer inventory, component checksums, prefix structure, managed process sequence, Steam launch path/arguments and bounded installation/readiness/compatibility logs.
