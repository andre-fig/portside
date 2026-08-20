# Artifact security

Every artifact record contains component, version, channel, source snapshot,
Portside build, origin metadata, license, filename, size, SHA-256, optional
signature, private storage key, provenance/SBOM, status and
verification/promotion timestamps. Source snapshots, runtime builds, releases,
promotions and rollbacks are separate records in Prisma. The artifact
lifecycle is:

```text
discovered -> downloading -> quarantined -> verified -> testing -> approved -> production
                                                                            \-> rejected/deprecated
```

Staging synchronization accepts only HTTPS URLs on the configured allowlist,
does not follow an unapproved redirect, enforces a maximum download size,
hashes before extraction and uses idempotency keys. Production artifacts must
reference a verified source snapshot and successful Portside build and must be
served from the Portside artifact-host allowlist. Steam's Windows installer
remains a Valve official download performed by the approved `steam` verb;
Portside does not mirror it.

Production clients use only the Portside API host and signed temporary object
Upstream source URLs remain provenance and development-only source data, not a
runtime dependency of a commercial installation.

Replicate approved objects to a second S3-compatible location. If that backup
is unavailable, keep the primary installation path working and create an
audited `secondary_backup_pending` operational alert. Never silently replace a
verified object with a changed download. A production release is promoted
explicitly and rollback creates an auditable rollback record while retaining
the previous object.
