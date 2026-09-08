#!/bin/sh
set -eu
umask 077
test -n "$CODESIGN_P12_BASE64"
test -n "$CODESIGN_P12_PASSWORD"
if [ -z "$CODESIGN_CERT_PEM" ] && [ -z "$CODESIGN_CERT_BASE64" ]; then
  echo "Missing Developer ID certificate secret" >&2
  exit 1
fi
SIGNING_KEYCHAIN="$RUNNER_TEMP/portside-runtime-signing.keychain-db"
SIGNING_P12="$RUNNER_TEMP/portside-runtime-developer-id.p12"
SIGNING_CERT="$RUNNER_TEMP/portside-runtime-developer-id.cer"
SIGNING_PRIVATE_KEY="$RUNNER_TEMP/portside-runtime-developer-id-private.key"
SIGNING_EMBEDDED_CERT="$RUNNER_TEMP/portside-runtime-developer-id-embedded.cer"
SIGNING_COMBINED_P12="$RUNNER_TEMP/portside-runtime-developer-id-combined.p12"
trap 'rm -f "$SIGNING_P12" "$SIGNING_CERT" "$SIGNING_PRIVATE_KEY" "$SIGNING_EMBEDDED_CERT" "$SIGNING_COMBINED_P12"' EXIT
security create-keychain -p '' "$SIGNING_KEYCHAIN"
security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
security unlock-keychain -p '' "$SIGNING_KEYCHAIN"
printf '%s' "$CODESIGN_P12_BASE64" | base64 -D > "$SIGNING_P12"
if [ -n "$CODESIGN_CERT_PEM" ]; then
  printf '%s\n' "$CODESIGN_CERT_PEM" > "$SIGNING_CERT"
else
  printf '%s' "$CODESIGN_CERT_BASE64" | base64 -D > "$SIGNING_CERT"
fi
if [ -n "$CODESIGN_CERT_PEM" ]; then
  openssl x509 -in "$SIGNING_CERT" -noout
else
  openssl x509 -inform der -in "$SIGNING_CERT" -noout
fi
security import "$SIGNING_P12" -P "$CODESIGN_P12_PASSWORD" -A -f pkcs12 -k "$SIGNING_KEYCHAIN"
security import "$SIGNING_CERT" -A -f pemseq -t cert -k "$SIGNING_KEYCHAIN" || true
security set-key-partition-list -S apple-tool:,apple: -s -k '' "$SIGNING_KEYCHAIN"
security list-keychains -d user -s "$SIGNING_KEYCHAIN"
security default-keychain -s "$SIGNING_KEYCHAIN"
signing_identity="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | awk -F '"' '/Developer ID Application:/{print $2; exit}')"
if [ -n "$signing_identity" ]; then
  printf 'PORTSIDE_CODESIGN_IDENTITY=%s\n' "$signing_identity" >> "$GITHUB_ENV"
  exit 0
fi
export PORTSIDE_P12_PASSWORD="$CODESIGN_P12_PASSWORD"
if ! openssl pkcs12 -in "$SIGNING_P12" -nocerts -nodes \
  -passin env:PORTSIDE_P12_PASSWORD -out "$SIGNING_PRIVATE_KEY" 2>/dev/null; then
  echo "Unable to decrypt the Developer ID PKCS#12; verify PORTSIDE_CODESIGN_P12_PASSWORD" >&2
  exit 1
fi
private_key_hash="$(openssl pkey -in "$SIGNING_PRIVATE_KEY" -pubout -outform der 2>/dev/null | shasum -a 256 | awk '{print $1}')"
if openssl pkcs12 -in "$SIGNING_P12" -clcerts -nokeys \
  -passin env:PORTSIDE_P12_PASSWORD -out "$SIGNING_EMBEDDED_CERT" 2>/dev/null \
  && openssl x509 -in "$SIGNING_EMBEDDED_CERT" -noout >/dev/null 2>&1; then
  embedded_certificate_key_hash="$(openssl x509 -in "$SIGNING_EMBEDDED_CERT" -pubkey -noout | openssl pkey -pubin -outform der 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  if [ "$private_key_hash" = "$embedded_certificate_key_hash" ]; then
    cp "$SIGNING_EMBEDDED_CERT" "$SIGNING_CERT"
    security import "$SIGNING_CERT" -A -f pemseq -t cert -k "$SIGNING_KEYCHAIN" || true
    security set-key-partition-list -S apple-tool:,apple: -s -k '' "$SIGNING_KEYCHAIN"
    if security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | grep -F "$PORTSIDE_CODESIGN_IDENTITY"; then
      exit 0
    fi
  fi
fi
certificate_key_hash="$(openssl x509 -in "$SIGNING_CERT" -pubkey -noout | openssl pkey -pubin -outform der 2>/dev/null | shasum -a 256 | awk '{print $1}')"
test -n "$private_key_hash" && test -n "$certificate_key_hash"
if [ "$private_key_hash" != "$certificate_key_hash" ]; then
  echo "Developer ID certificate does not match the exported private key" >&2
  exit 1
fi
openssl pkcs12 -export -inkey "$SIGNING_PRIVATE_KEY" -in "$SIGNING_CERT" \
  -name "$PORTSIDE_CODESIGN_IDENTITY" -passout env:PORTSIDE_P12_PASSWORD \
  -out "$SIGNING_COMBINED_P12" 2>/dev/null
security import "$SIGNING_COMBINED_P12" -P "$CODESIGN_P12_PASSWORD" -A -f pkcs12 -k "$SIGNING_KEYCHAIN"
signing_identity="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | awk -F '"' '/Developer ID Application:/{print $2; exit}')"
test -n "$signing_identity"
printf 'PORTSIDE_CODESIGN_IDENTITY=%s\n' "$signing_identity" >> "$GITHUB_ENV"
