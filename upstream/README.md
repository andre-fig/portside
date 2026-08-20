# Portside upstream source snapshots

`upstream/lock.json` is the canonical provenance record for the source snapshots
under `vendor/`. Each entry records the original repository, the complete commit
ID, commit date, license information, clone/LFS/submodule state, exclusions and
the deterministic checksum of the imported snapshot.

## Imported sources

- `vendor/wine/` contains the pinned Wine source tree from the Sikarugir Wine
  repository. It was cloned shallowly with `--filter=blob:none` and contains no
  nested Git repository.
- `vendor/winetricks/` contains the pinned winetricks source and notices.
- `vendor/foss-sources/` contains the available LGPL-2.1 source snapshot for the
  Configure project. The committed Mach-O helpers `Configure/cabextract` and
  `Configure/fntoggle` were intentionally not imported as compiled artifacts.
- `vendor/sikarugir/`, `vendor/wrapper/` and `vendor/engines/` preserve the
  source repositories exactly as available at the pinned commits, including
  README files and notices.
- Creator remains provenance-only. It is not copied into Portside because the
  current source/build path does not prove that its interface is required.

## Build inputs and recorded limitations

The pinned Wrapper repository contains only `README.md` and
`NewestVersion.txt`. The pinned Engines repository contains only
`EngineList.txt`, `README.md` and `index.html`. Neither contains the source or
build recipe for `Template-1.0.11` or `WS12WineSikarugir10.0_6`.

Portside does not use those metadata-only snapshots as executable build input.
The wrapper/template and native host are implemented in Portside source, and
the engine recipe builds from `vendor/wine`. The build still stops on missing
toolchain or library inputs and never falls back silently to a compiled
external release.

## Synchronization rules

Run `scripts/upstream/sync.sh` from the repository root. It downloads each
authorized source into a temporary directory, resolves the pinned commit,
checks submodules and Git LFS, validates the source tree, computes a snapshot
checksum and updates `upstream/lock.json`. The GitHub workflow opens a pull
request for changes; it never merges or publishes them automatically.

The source snapshots retain their upstream licenses, copyright notices and
build scripts. See `RUNTIME_LICENSES.md` and `THIRD_PARTY_NOTICES.md` before
promoting any generated runtime artifact.
