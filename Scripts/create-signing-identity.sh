#!/usr/bin/env bash
# Creates a self-signed code-signing identity, once, so macOS permissions
# survive rebuilds.
#
# Why this exists: MacToys is signed ad-hoc, which means it has no stable
# identity. macOS ties Accessibility and Screen Recording grants to the app's
# code signature, and an ad-hoc signature changes every single time the app is
# rebuilt — so every rebuild silently revokes the permissions you granted, while
# the checkbox in System Settings still looks switched on. Signing with a
# certificate instead keeps the identity stable, so a grant given once keeps
# applying.
#
# This touches your login keychain, so run it yourself; it will ask for your
# password. It creates a local certificate only — it grants nobody any access,
# and nothing leaves this machine. Undo with:
#   security delete-certificate -c "MacToys Self-Signed" ~/Library/Keychains/login.keychain-db
set -euo pipefail

NAME="MacToys Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "==> '$NAME' already exists — nothing to do."
    echo "    Scripts/bundle.sh will use it automatically."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = MacToys Self-Signed
[ ext ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CNF

echo "==> Generating certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass: 2>/dev/null

echo "==> Importing into your login keychain (may ask for your password)"
security import "$TMP/id.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P "" >/dev/null

echo "==> Trusting it for code signing (will ask for your password)"
sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign -k /Library/Keychains/System.keychain "$TMP/cert.pem"

# Lets codesign use the key without a prompt on every build.
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "==> Done. Rebuild with 'make app', then grant Accessibility once more."
    echo "    From now on the grant will survive rebuilds."
else
    echo "==> The identity was not created. MacToys will keep signing ad-hoc," >&2
    echo "    which still works — permissions will just reset on each rebuild." >&2
    exit 1
fi
