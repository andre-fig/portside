# Portside runtime build

The runtime is built from source in the repository. The generated runtime
contains three separately verified components:

- `PortsideWrapper-<version>.tar.xz`: `PortsideBaseline.app`, including the
  compiled `PortsideRuntimeHost` and WineD3D-only configuration;
- `PortsideWineEngine-<version>.tar.xz`: Wine built from `vendor/wine` with
  native macOS tools and 32/64-bit Windows PE targets;
- `PortsideWinetricks-<version>.tar.xz`: the source and notices from
  `vendor/winetricks`.

## Local build

Install the exact toolchain versions in `upstream/dependencies.json`, then run:

```sh
PORTSIDE_RUNTIME_VERSION=0.1.0 \
PORTSIDE_RUNTIME_CHANNEL=staging \
PORTSIDE_RUNTIME_ARTIFACT_URL_PREFIX=https://artifacts.example.invalid/staging/runtime/ \
./scripts/build-runtime/build.sh
```

The URL is used only to construct the unsigned staging manifest. The build
does not download a compiled wrapper, engine or Steam installer. Steam remains
an end-user installation performed by the `steam` winetricks verb.

The engine recipe defaults to the host architecture (`arm64` on Apple silicon)
and can be given an explicit `PORTSIDE_WINE_ARCH` only when matching target
libraries are available. It records the source snapshot, Portside commit,
build ID, artifact checksums and toolchain in `provenance.json`. A missing
required dependency is a hard failure; `--without-freetype` and prebuilt
runtime substitutions are not accepted by the production recipe.

## Current validation

The wrapper and winetricks source archives have been produced locally. A real
Wine build is still running/being validated on the current Mac; no engine,
Steam installation or graphical result is considered successful until the
build exits cleanly and the acceptance procedure in `docs/VALIDATION.md` is
completed. The checked-in lockfile is updated only with evidence from a
completed build.

## Publication

`build-runtime.yml` builds on the pinned macOS runner, signs the manifest and
publishes only to staging. `publish_runtime_staging.sh` writes the archives,
manifest, provenance and SBOM to the primary and secondary object stores.
Production requires a separate explicit promotion and retains prior versions
for rollback. The backend rejects a production component without source
provenance, a Portside build ID, successful validation and promotion state.
