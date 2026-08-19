#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INPUT="${PORTSIDE_RUNTIME_MANIFEST_INPUT:?Set a JSON manifest with signature:null}"
KEY_FILE="${PORTSIDE_MANIFEST_SIGNING_KEY_FILE:?Set a CI-only Ed25519 private-key file outside the repository}"
OUTPUT="${PORTSIDE_MANIFEST_OUTPUT:-$ROOT_DIR/build/releases/runtime-manifest.json}"
[ -f "$INPUT" ] || { echo "Missing unsigned runtime manifest $INPUT" >&2; exit 1; }
[ -f "$KEY_FILE" ] || { echo "Missing manifest signing key" >&2; exit 1; }
case "$KEY_FILE" in "$ROOT_DIR"/*) echo "Signing keys must remain outside the repository" >&2; exit 1;; esac

INPUT="$INPUT" KEY_FILE="$KEY_FILE" OUTPUT="$OUTPUT" node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
import { sign, createPrivateKey } from 'node:crypto';
const sort = (value) => Array.isArray(value) ? value.map(sort) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, sort(value[key])])) : value;
const input = JSON.parse(readFileSync(process.env.INPUT, 'utf8'));
input.signature = null;
const canonical = JSON.stringify(sort(input));
const key = createPrivateKey(readFileSync(process.env.KEY_FILE));
input.signature = sign(null, Buffer.from(canonical), key).toString('base64');
writeFileSync(process.env.OUTPUT, JSON.stringify(sort(input), null, 2) + '\n', { mode: 0o644 });
NODE

echo "Created signed runtime manifest at $OUTPUT"
