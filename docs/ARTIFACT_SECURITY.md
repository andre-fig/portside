# Artifact security

Every artifact record contains component, version, channel, origin URL and
repository, source commit/tag, license, filename, size, SHA-256, optional
upstream signature, private storage key, status and verification/promotion
timestamps. The lifecycle is:

```text
discovered -> downloading -> quarantined -> verified -> testing -> approved -> production
                                                                            \-> rejected/deprecated
```

The sync worker accepts only HTTPS URLs on the configured allowlist, does not
follow an unapproved redirect, enforces a maximum download size, hashes before
extraction, rejects unsafe archive paths and uses idempotency keys. Steam's
Windows installer remains a Valve official download performed by the approved
`steam` verb; Portside does not mirror it without a separate authorization.

Production clients use only the Portside API host and signed temporary object
URLs. GitHub/Sikarugir URLs remain provenance and development-only source data,
not a runtime dependency of a commercial installation.

Replicate approved objects to a second S3-compatible location. If that backup
is unavailable, keep the primary installation path working and create an
audited `secondary_backup_pending` operational alert. Never silently replace a
verified object with a changed download.
