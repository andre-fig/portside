# Licensing and commercial distribution

## Portside code

The repository currently has no third-party Swift package dependencies. Portside-owned code is not granted a commercial distribution license by this document; add the project’s chosen license before shipping.

## Runtime status

The app does not bundle Wine, CrossOver, Game Porting Toolkit, D3DMetal, Rosetta, GStreamer, DXMT, or game binaries. It downloads Wine Staging 11.15 from the pinned Gcenx release and GStreamer 1.28.5 from the official GStreamer site at setup time, verifies both, and stores them under the user’s Portside directory. Wine source is LGPL-2.1-or-later; GStreamer is LGPL-2.1-or-later plus component-specific licenses. Gcenx’s packaging repository does not expose an SPDX license in its GitHub metadata, so commercial redistribution of that packaged artifact still requires upstream confirmation. Portside currently downloads rather than redistributes it.

DXMT is intentionally not installed: its current GitHub metadata reports `NOASSERTION` for the license. Direct3D 9/10/11 use WineD3D shipped with the Wine build.

## Steam

Portside does not include Steam. It downloads the Windows installer at setup time from Valve’s official CDN and does not modify the Steam client. Valve/Steam trademarks remain the property of Valve Corporation. Portside is independent and is not affiliated with or endorsed by Valve Corporation.

## Release gates

Before any commercial release, obtain legal review for the selected runtime package, its GStreamer contents, graphics layer, code signing/update mechanism, Valve distribution terms, macOS privacy disclosures, and final notices. Runtime download-at-install does not eliminate license obligations.
