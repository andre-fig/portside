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
PORTSIDE_RUNTIME_CHANNEL=production \
PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX=https://api.example.invalid/v1/runtime/artifacts/production/ \
./scripts/build-runtime/build.sh
```

The URL is used only to construct the unsigned production manifest. It must be the
Portside API route, not the private bucket URL; the API redirects to a
short-lived S3-signed URL for `runtime/production/<fileName>`. The build does not
download a compiled wrapper, engine or Steam installer. Steam remains
an end-user installation performed by the `steam` winetricks verb.

The engine recipe defaults to the host architecture (`arm64` on Apple silicon)
and can be given an explicit `PORTSIDE_WINE_ARCH` only when matching target
libraries are available. It records the source snapshot, Portside commit,
build ID, artifact checksums and toolchain in `provenance.json`. A missing
required dependency is a hard failure; `--without-freetype` and prebuilt
runtime substitutions are not accepted by the production recipe.

## Current validation

The local macOS build has produced the Portside wrapper, Wine engine and
Winetricks archives from checked-in sources. The clean archive layout and
unsigned manifest checks pass. The GitHub Actions validation build uses the
protected `production` Environment and is configured
with the manifest key and separate primary/secondary Railway bucket
credentials; its latest validated execution signed the manifest and replicated
the runtime evidence to both buckets. This proves source compilation,
signature and dual storage, not Steam installation or a graphical result. The
clean GUI procedure in `docs/VALIDATION.md` still requires a logged-in
self-hosted Mac. The lockfile is not updated from an incomplete build.

## Publication

`build-runtime.yml` builds on the pinned macOS runner after source/runtime
merges on `main` (or a manual dispatch), signs the manifest and publishes the
production channel. It is not triggered by ordinary app/backend/docs
changes or by edits to its own workflow file. The Wine engine is keyed by the
vendored snapshot, compiler flags, architecture and macOS/Xcode toolchain; a
matching cache assembles the archive without rerunning the full Wine compile.
Use the manual `force_rebuild=true` input only when the cache itself must be
discarded and Wine must be rebuilt from source.
The protected GitHub Environment `production` must
provide the manifest-signing key, both bucket names, an HTTPS
`PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX` and
S3-compatible credentials for both Railway buckets (`PORTSIDE_S3_ACCESS_KEY_ID`,
`PORTSIDE_S3_SECRET_ACCESS_KEY`, `PORTSIDE_S3_REGION`,
`PORTSIDE_S3_ENDPOINT` and the corresponding `PORTSIDE_SECONDARY_S3_*`
values). `publish_runtime.sh` writes the archives,
manifest, provenance and SBOM to the primary and secondary object stores in
parallel per object.
The Railway buckets remain private. The manifest now points to the stable
Portside API route; the backend creates a short-lived signed object URL and
returns a redirect without exposing bucket credentials. This workflow proves
source build, manifest signature and dual-bucket replication. End-user desktop
download still requires the production manifest to be registered in the API
and a clean-install validation. Previous production versions are retained for
rollback, and the backend rejects a component without source provenance, a
Portside build ID and successful validation.

## Reusing a validated runtime

`release-production.yml` does not compile Wine or the wrapper. It selects the
latest successful `Build Portside Runtime` run on `main`, downloads the small
metadata artifact and reuses its signed evidence for the app release. The
full `portside-runtime-production-<version>` artifact remains available for
evidence and rollback, but is no longer transferred during a normal release.
The runtime version is read from `runtime-manifest-unsigned.json`. The release
workflow uses that validated runtime version automatically for the app release,
so no version input is required. A source/runtime change still requires a new
runtime build. If an older runtime run has no metadata artifact, the release
falls back to its full evidence artifact for compatibility.

The runtime archives are published by `build-runtime.yml` directly to the
production prefix before the app release starts. The release job reuses the
production manifest metadata and publishes the app assets afterward.
