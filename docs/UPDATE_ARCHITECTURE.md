# Update architecture

Portside.app updates and runtime updates are separate:

- Sparkle 2 updates the signed/notarized `Portside.app` through the Portside
  appcast. Its Ed25519 public key is embedded in the app; the private key stays
  in CI/Keychain.
- The Portside runtime manifest updates wrapper/engine/winetricks metadata and
  artifacts. It is signed with a different Ed25519 key and validated before
  download or extraction.

A commercial release first requires the writable, installed bundle at
`/Applications/Portside.app`. A mounted installer, App Translocation or other
location shows the move-and-reopen gate. Debug and explicitly packaged
`development` builds log an English exemption. Components resolve through
Foundation bundle APIs independently of that location gate.

Every accepted launch initializes Sparkle and immediately probes the appcast,
including first launch without runtime, Steam or previous state. Bootstrap
awaits an explicit result before checking or downloading the runtime. The probe
has a 20-second deadline; a late probe cannot initiate installation. An available
update enters a separate installation cycle, respecting Sparkle's automatic
installation preference and using its standard UI for required confirmation.
Critical updates keep Steam blocked until installation and relaunch complete.
A 10-minute installation deadline fails closed and never releases runtime work
while an installer may still be running.

A minimal relaunch receipt records source and expected CFBundleVersion. The next
process verifies the expected version before runtime work. An unsuccessful
relaunch requires an explicit retry, preventing automatic relaunch loops. No
transient bootstrap stage is persisted. Offline lookup can release a valid
version; a minimum version from an authenticated runtime manifest remains a
block even when a later request is offline. An appcast critical marker is a
session requirement, not a substitute for that separately signed policy.

A failed runtime update is prepared atomically and leaves the
existing wrapper, prefix and Steam data in place. The backend retains at least
three usable runtime versions: current production, previous production and
the last proven stable version. A shared process lease prevents the background
runtime preparer from racing app preflight or foreground runtime installation;
legacy runtime-only workers are authenticated and stopped before the lease is
acquired. No Steam or compatibility process is included in that handoff.

See [bootstrap validation](BOOTSTRAP_VALIDATION.md) for the state transitions,
repeatable checks and the separate evidence/limitations of real DMG and updater
testing.

Production uses one appcast and manifest channel. A new version is never
published until checksum, signature, license inventory and real macOS
validation have passed.

The app rejects unsigned or malformed manifests, invalid hashes, incompatible
minimum versions, unauthorized hosts and downgrades outside the signed
rollback target. An existing working runtime remains usable when the backend
is offline.
