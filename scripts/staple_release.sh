#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { echo "usage: staple_release.sh APP_OR_DMG" >&2; exit 2; }
staple_target="$1"
[ -e "$staple_target" ] || { echo "Missing notarized artifact" >&2; exit 1; }

# Called only after notarytool accepts the submission. A successful submission
# may precede ticket availability in CloudKit. Retry only the observed lookup
# failure, never a rejected submission or a ticket/signature validation failure.
staple_log="$(mktemp "${TMPDIR:-/tmp}/portside-stapler.XXXXXX")"
trap 'rm -f "$staple_log"' EXIT
staple_attempt=1
staple_delay=5
while :; do
    if LC_ALL=C xcrun stapler staple "$staple_target" >"$staple_log" 2>&1; then
        cat "$staple_log"
        exit 0
    else
        staple_status=$?
    fi
    cat "$staple_log"
    if [ "$staple_status" -ne 65 ] || [ "$staple_attempt" -ge 5 ] ||
       ! grep -Fq 'CloudKit query for ' "$staple_log" ||
       ! grep -Fq 'Could not find base64 encoded ticket in response' "$staple_log"; then
        exit "$staple_status"
    fi
    echo "Notarization ticket lookup failed; retrying stapling in ${staple_delay}s (attempt $((staple_attempt + 1))/5)." >&2
    sleep "$staple_delay"
    staple_attempt=$((staple_attempt + 1))
    staple_delay=$((staple_delay * 2))
done
