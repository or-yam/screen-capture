#!/usr/bin/env bash
set -euo pipefail
umask 077

IDENTITY="ScreenCaptureAll Diagnostics Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TEMP_BASE=${TMPDIR:-/private/var/folders/w0/frvdsln930b30h7_l26g16240000gn/T/opencode}

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate already exists; leaving its key and trust settings unchanged."
    security find-identity -v -p codesigning "$KEYCHAIN"
    exit 0
fi

TEMP_DIR=$(mktemp -d "$TEMP_BASE/capture-signing.XXXXXX")
export CAPTURE_SIGNING_P12_PASSWORD=$(/usr/bin/openssl rand -hex 24)
cleanup() {
    rm -f "$TEMP_DIR/openssl.cnf" "$TEMP_DIR/key.pem" "$TEMP_DIR/cert.pem" "$TEMP_DIR/identity.p12"
    rmdir "$TEMP_DIR"
    unset CAPTURE_SIGNING_P12_PASSWORD
}
trap cleanup EXIT

cat > "$TEMP_DIR/openssl.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = ScreenCaptureAll Diagnostics Development
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
CONFIG

/usr/bin/openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
    -config "$TEMP_DIR/openssl.cnf" -keyout "$TEMP_DIR/key.pem" -out "$TEMP_DIR/cert.pem"
# Apple's LibreSSL produces a PKCS#12 container compatible with Keychain import.
/usr/bin/openssl pkcs12 -export -name "$IDENTITY" -passout env:CAPTURE_SIGNING_P12_PASSWORD \
    -inkey "$TEMP_DIR/key.pem" -in "$TEMP_DIR/cert.pem" -out "$TEMP_DIR/identity.p12"

# Only codesign is allowed automatic private-key access; do not unlock the
# keychain or change access rules for unrelated keys.
security import "$TEMP_DIR/identity.p12" -k "$KEYCHAIN" -P "$CAPTURE_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
# User-domain trust, restricted to code signing (not TLS, email, or system roots).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TEMP_DIR/cert.pem"
security find-identity -v -p codesigning "$KEYCHAIN"
echo "Diagnostic signing identity installed: $IDENTITY"
