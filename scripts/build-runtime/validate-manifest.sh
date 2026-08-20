#!/bin/sh
set -eu

MANIFEST="${1:?usage: validate-manifest.sh MANIFEST.json}"
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
[ -f "$MANIFEST" ] || { echo "manifest does not exist: $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for manifest validation" >&2; exit 1; }

jq -e '
  (.schemaVersion | numbers) and
  (.channel | IN("staging", "production")) and
  (.buildStatus | IN("staging", "production")) and
  (.builtBy == "Portside") and
  ((.components | length) == 3) and
  ([.components[].component] | sort) == ["engine", "winetricks", "wrapper"] and
  ([.components[] | select(.builtBy != "Portside" or (.sha256 | test("^[0-9a-fA-F]{64}$") | not) or (.size | numbers) <= 0 or (.downloadURL | startswith("https://") | not))] | length) == 0 and
  ((.signature == null) or (.signature | strings | length > 0))
' "$MANIFEST" >/dev/null

if rg -n -i 'Sikarugir|Template-1\.0|WS12WineSikarugir|raw\.githubusercontent\.com|github\.com/Sikarugir-App' "$MANIFEST"; then
    echo "manifest contains a forbidden upstream artifact reference" >&2
    exit 1
fi
echo "runtime manifest validated: $MANIFEST"
