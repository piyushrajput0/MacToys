#!/usr/bin/env bash
# Creates the certificate that every MacToys *release* is signed with, and
# hands it to GitHub Actions as a secret. Run this once, ever.
#
# Why this exists: macOS ties Accessibility and Screen Recording grants to an
# app's code signature. Releases signed ad-hoc get a new signature every build,
# so every update would silently revoke the permissions people granted — and the
# checkboxes in System Settings would still look switched on. One certificate,
# reused for every release, keeps that identity stable, so a grant given once
# keeps applying across updates.
#
# This is NOT an Apple Developer ID. It costs nothing, and it does not stop
# Gatekeeper warning on first launch — only Apple's $99/year programme does
# that. It solves the permissions problem, which is the one that actually
# bites people on every single update.
#
# Keep the .p12 this produces, or at least the secret in GitHub. Losing it means
# the next release signs with a different identity and everyone re-grants
# permissions once.
set -euo pipefail

NAME="MacToys Release"
REPO="piyushrajput0/MacToys"
OUT="${1:-$HOME/mactoys-release-identity.p12}"

command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 1; }

if [ -e "$OUT" ]; then
    echo "==> $OUT already exists." >&2
    echo "    Reuse it — generating a new one resets everyone's permissions." >&2
    echo "    To upload the existing one to GitHub:" >&2
    echo "      base64 -i '$OUT' | gh secret set MACTOYS_SIGNING_CERT_P12 --repo $REPO" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A password is required: `security import` in CI refuses an empty one on a
# fresh keychain, and it keeps the secret useless on its own if it ever leaks.
PASSWORD="$(openssl rand -base64 24)"

cat > "$TMP/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CNF

echo "==> Generating the release certificate (valid 10 years)"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null
# The legacy algorithm flags are not optional. OpenSSL 3.x writes PKCS#12 with
# an AES/SHA-256 profile that Apple's security(1) cannot read, and it reports the
# failure as "MAC verification failed ... (wrong password?)" — which sends you
# hunting for a password bug that is not there. 3DES + SHA-1 is what it wants.
openssl pkcs12 -export -out "$OUT" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PASSWORD"
chmod 600 "$OUT"

echo "==> Wrote $OUT"

# Prove the thing actually imports and signs before uploading it as a secret.
# Otherwise the first sign that anything is wrong is a failed release build.
echo "==> Verifying it imports and signs"
VERIFY_KC="$TMP/verify.keychain-db"
security create-keychain -p verify "$VERIFY_KC"
security unlock-keychain -p verify "$VERIFY_KC"
if ! security import "$OUT" -k "$VERIFY_KC" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null 2>&1; then
    security delete-keychain "$VERIFY_KC" 2>/dev/null || true
    rm -f "$OUT"
    echo "    The certificate did not import. Nothing was uploaded." >&2
    echo "    openssl in use: $(command -v openssl) ($(openssl version))" >&2
    exit 1
fi
# No -v: it filters to trust-chained identities, which a self-signed certificate
# is not, even though codesign signs with it happily.
if ! security find-identity -p codesigning "$VERIFY_KC" | grep -q "$NAME"; then
    security delete-keychain "$VERIFY_KC" 2>/dev/null || true
    rm -f "$OUT"
    echo "    The identity imported but is not usable for code signing." >&2
    exit 1
fi
security delete-keychain "$VERIFY_KC" 2>/dev/null || true
echo "    OK"
echo

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    echo "==> Uploading both secrets to $REPO"
    base64 -i "$OUT" | gh secret set MACTOYS_SIGNING_CERT_P12 --repo "$REPO"
    printf '%s' "$PASSWORD" | gh secret set MACTOYS_SIGNING_CERT_PASSWORD --repo "$REPO"
    echo
    echo "==> Done. Tag a release and it will be signed:"
    echo "      git tag v1.0.0 && git push origin v1.0.0"
else
    echo "==> gh is not installed or not logged in. Add these two secrets by hand"
    echo "    at https://github.com/$REPO/settings/secrets/actions"
    echo
    echo "    MACTOYS_SIGNING_CERT_P12       (base64 of the .p12)"
    echo "    MACTOYS_SIGNING_CERT_PASSWORD  $PASSWORD"
    echo
    echo "    Get the base64 with:"
    echo "      base64 -i '$OUT' | pbcopy"
fi

echo
echo "    Store the password somewhere safe — it is not recoverable:"
echo "      $PASSWORD"
