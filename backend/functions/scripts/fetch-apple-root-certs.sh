#!/usr/bin/env bash
# Downloads Apple's public root certificates used by SignedDataVerifier (src/apple.ts) into
# backend/functions/certs/. Source: Apple PKI, https://www.apple.com/certificateauthority/
# Run once (owner or CI with internet), compare the printed SHA-256 fingerprints with the ones
# Apple publishes on that page, then commit the .cer files (they are public, not secrets).
# Without these files iOS purchase verification fails closed (no entitlement).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p certs
for name in AppleRootCA-G3 AppleRootCA-G2 AppleIncRootCertificate; do
  curl --fail --silent --show-error --location -o "certs/${name}.cer" "https://www.apple.com/certificateauthority/${name}.cer"
  echo "${name}.cer"
  openssl x509 -inform DER -in "certs/${name}.cer" -noout -subject -enddate -fingerprint -sha256
done
echo "Compare the fingerprints above with https://www.apple.com/certificateauthority/ before committing."
