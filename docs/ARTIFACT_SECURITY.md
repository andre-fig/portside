# Artifact security entry point

The implemented trust model and its limits are in [SECURITY](SECURITY.md).
[BACKEND](BACKEND.md) describes artifact/source/build/release records and
administrative validation; [RELEASE](RELEASE.md) describes storage and publication.

This compatibility path replaces duplicated guarantees. In particular, a
structural manifest check is not signature verification, an administrative
production status is not GUI acceptance, and a versioned storage key is not
enforced immutability. Current operational evidence is in [STATUS](STATUS.md).
