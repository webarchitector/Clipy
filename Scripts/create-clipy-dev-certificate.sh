#!/usr/bin/env bash

set -euo pipefail

identity_name="Clipy Dev"
keychain_path="${HOME}/Library/Keychains/login.keychain-db"
archive_password="clipydev"

for command_name in openssl security; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command not found: $command_name" >&2
        exit 1
    fi
done

if security find-identity -v -p codesigning "$keychain_path" 2>/dev/null \
    | grep -Fq "\"${identity_name}\""; then
    echo "Code-signing identity '${identity_name}' already exists."
    security find-identity -v -p codesigning "$keychain_path" | grep -F "\"${identity_name}\""
    exit 0
fi

certificate_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipy-dev-certificate.XXXXXX")"
cleanup() {
    rm -rf "$certificate_temp_dir"
}
trap cleanup EXIT

cat > "$certificate_temp_dir/openssl.cnf" <<'EOF'
[req]
default_bits = 2048
distinguished_name = req_dn
req_extensions = v3_req
prompt = no

[req_dn]
CN = Clipy Dev

[v3_req]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "Creating self-signed '${identity_name}' certificate..."
openssl req \
    -x509 \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$certificate_temp_dir/key.pem" \
    -out "$certificate_temp_dir/cert.pem" \
    -days 3650 \
    -config "$certificate_temp_dir/openssl.cnf" \
    -extensions v3_req

openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$certificate_temp_dir/key.pem" \
    -in "$certificate_temp_dir/cert.pem" \
    -out "$certificate_temp_dir/identity.p12" \
    -password "pass:${archive_password}"

echo "Importing '${identity_name}' into ${keychain_path}..."
security import "$certificate_temp_dir/identity.p12" \
    -k "$keychain_path" \
    -P "$archive_password" \
    -T /usr/bin/codesign

echo "Trusting '${identity_name}' for code signing..."
security add-trusted-cert \
    -p codeSign \
    -k "$keychain_path" \
    "$certificate_temp_dir/cert.pem"

if ! security find-identity -v -p codesigning "$keychain_path" \
    | grep -Fq "\"${identity_name}\""; then
    echo "Certificate was imported, but '${identity_name}' is not a valid code-signing identity." >&2
    exit 1
fi

echo
echo "Created code-signing identity:"
security find-identity -v -p codesigning "$keychain_path" | grep -F "\"${identity_name}\""
echo
echo "You can now build Clipy with CODE_SIGN_IDENTITY=\"${identity_name}\"."
