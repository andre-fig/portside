# Update architecture

Portside.app updates and runtime updates are separate:

- Sparkle 2 updates the signed/notarized `Portside.app` through the Portside
  appcast. Its Ed25519 public key is embedded in the app; the private key stays
  in CI/Keychain.
- The Portside runtime manifest updates wrapper/engine/winetricks metadata and
  artifacts. It is signed with a different Ed25519 key and validated before
  download or extraction.

The app starts Sparkle asynchronously at launch. An unavailable feed does not
delay Steam. A failed runtime update is staged atomically and leaves the
existing wrapper, prefix and Steam data in place. The backend retains at least
three usable runtime versions: current production, previous production and
the last proven stable version.

Staging uses a separate appcast and manifest channel. The newest upstream
version is never promoted automatically. Promotion requires checksum,
signature, license inventory and real macOS validation.

The app rejects unsigned or malformed manifests, invalid hashes, incompatible
minimum versions, unauthorized hosts and downgrades outside the signed
rollback target. An existing working runtime remains usable when the backend
is offline.
