# Rollback runbook

For a Portside.app update, stop promotion, keep the previous signed/notarized
archive and publish its appcast item through the authorized release workflow.
Sparkle must see an incrementing app version; emergency rollback should be a
new fixed build rather than an unsigned downgrade.

For a runtime release, select the last proven production release and call the
authenticated release rollback endpoint. The target must already have a
published production manifest:

```sh
curl --fail --request POST \
  --header "Authorization: Bearer $PORTSIDE_ADMIN_BEARER_TOKEN" \
  --header 'Content-Type: application/json' \
  --data '{"targetReleaseId":"<previous-release-id>","reason":"validated rollback"}' \
  "$PORTSIDE_API_BASE_URL/v1/admin/releases/<current-release-id>/rollback"
```

The backend supersedes the current manifest and republishes the signed target
manifest without deleting the current prefix or Steam data. The client stages
the previous component atomically and validates its hash. If validation fails,
leave the current runtime active and mark the artifact rejected. Record the
event in the audit log and verify a clean Steam launch on a real Mac.
