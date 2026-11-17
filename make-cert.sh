#!/bin/sh
# Create a self-signed code-signing identity in the login keychain, so builds
# have a stable signature and the Accessibility grant survives rebuilds.
# (An ad-hoc signature is tied to the exact binary hash, so every rebuild
# looks like a new app to macOS.)
#
# Usage: ./make-cert.sh "Common Name"
set -eu

NAME=${1:?usage: $0 "Common Name"}
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Signing certificate \"$NAME\" already exists."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=$(openssl rand -hex 16)

cat >"$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -passout "pass:$PASS" -out "$TMP/id.p12"

# -x: private key can't be exported again. -T: only codesign may use it
# without asking.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -x -T /usr/bin/codesign

echo "Created signing certificate \"$NAME\" in the login keychain."
echo "The first signing may ask to allow codesign to use the key: choose Always Allow."
