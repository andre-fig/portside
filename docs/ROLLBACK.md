# Rollback runbook

For a Portside.app update, stop promotion, keep the previous signed/notarized
archive and publish its appcast item through the authorized release workflow.
Sparkle must see an incrementing app version; emergency rollback should be a
new fixed build rather than an unsigned downgrade.

For a runtime, call the authenticated admin endpoint after selecting the last
proven stable manifest:

```sh
curl --fail --request POST \
  --header "Authorization: Bearer $PORTSIDE_ADMIN_BEARER_TOKEN" \
  --header 'Content-Type: application/json' \
  --data '{"rollbackVersion":"<signed-version>"}' \
  "$PORTSIDE_API_BASE_URL/v1/admin/artifacts/<artifact-id>/rollback"
```

The client stages the previous component atomically, validates its hash and
does not delete the current prefix or Steam data. If validation fails, leave
the current runtime active and mark the artifact rejected. Record the event in
the audit log and verify a clean Steam launch on a real Mac.
