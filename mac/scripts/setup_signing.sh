#!/usr/bin/env bash
# Create a stable self-signed code-signing identity so macOS TCC remembers
# microphone / screen-recording permission across local rebuilds.
#
# Without this, every `swift build` produces a fresh ad-hoc signature with
# a new cdhash. TCC drops the prior consent and re-prompts on each launch.
# A stable signing identity makes TCC track the app by identity + bundle
# ID instead, so permissions persist.
#
# Run once:
#   make trust
#
# Idempotent: if the identity already exists, the script exits successfully.
set -euo pipefail

IDENTITY="MeetingRecorder Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ signing identity '$IDENTITY' already in login keychain"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "→ generating self-signed code-signing certificate"
openssl req -newkey rsa:2048 -nodes \
    -keyout "$tmpdir/key.pem" \
    -x509 -days 3650 \
    -out "$tmpdir/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    >/dev/null 2>&1

openssl pkcs12 -export \
    -inkey "$tmpdir/key.pem" \
    -in "$tmpdir/cert.pem" \
    -out "$tmpdir/cert.p12" \
    -name "$IDENTITY" \
    -passout pass: \
    >/dev/null 2>&1

echo "→ importing into login keychain"
security import "$tmpdir/cert.p12" \
    -k "$KEYCHAIN" \
    -P "" \
    -A -T /usr/bin/codesign \
    >/dev/null

echo "✓ created identity '$IDENTITY'"
echo "  next build will codesign with it; macOS will remember permissions."
echo "  rebuild with: make build-release-signed"
