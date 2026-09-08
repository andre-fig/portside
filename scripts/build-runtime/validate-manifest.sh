#!/bin/sh
set -eu

MANIFEST="${1:?usage: validate-manifest.sh MANIFEST.json}"
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
[ -f "$MANIFEST" ] || { echo "manifest does not exist: $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for manifest validation" >&2; exit 1; }

jq -e '
  (.schemaVersion | numbers) and
  (.channel == "production") and
  (.buildStatus == "production") and
  (.builtBy == "Portside") and
  ((.integration // "directWine") | . == "directWine" or . == "sikarugir") and
  ((.components | length) == 3) and
  ([.components[].component] | sort) == ["engine", "winetricks", "wrapper"] and
  ([.components[] | select(.builtBy != "Portside" or (.sha256 | test("^[0-9a-fA-F]{64}$") | not) or (.size | numbers) <= 0 or (.downloadURL | startswith("https://") | not))] | length) == 0 and
  ((.signature == null) or (.signature | strings | length > 0))
' "$MANIFEST" >/dev/null

# Producer/provenance names may identify the approved upstream composition.
# Actual downloads remain authenticated Portside routes, never upstream URLs.
jq -e '[.components[].downloadURL | select(test("github\\.com|githubusercontent\\.com|example\\.invalid"; "i"))] | length == 0' "$MANIFEST" >/dev/null
if [ "$(jq -r '.integration // "directWine"' "$MANIFEST")" = sikarugir ]; then
    jq -e 'all(.components[]; .buildOperation == "assembly" and .upstreamProducer == "Sikarugir")' "$MANIFEST" >/dev/null
fi
echo "runtime manifest validated: $MANIFEST"
