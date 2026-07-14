#!/usr/bin/env bash

# Issues or renews the Let's Encrypt certificate via DNS-01 against DuckDNS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -a
source .env
set +a

MODE="${1:-prod}"
STAGING_FLAG=""
if [ "$MODE" = "staging" ]; then
    STAGING_FLAG="--staging"
fi

mkdir -p letsencrypt

COMMON_ARGS=(
    --rm
    -e "NC_DOMAIN=${NC_DOMAIN}"
    -e "DUCKDNS_TOKEN=${DUCKDNS_TOKEN}"
    -v "${PROJECT_ROOT}/letsencrypt:/etc/letsencrypt"
    -v "${PROJECT_ROOT}/certbot:/scripts:ro"
)

CERT_FILE="letsencrypt/live/${NC_DOMAIN}/cert.pem"

if [ -f "$CERT_FILE" ] && [ ! -L "$CERT_FILE" ]; then
    # cert.pem exists but isn't certbot's expected symlink into archive/ -
    # e.g. this letsencrypt/ was restored from a zip archive, and zip (in
    # particular Windows Explorer's built-in extractor) doesn't preserve
    # Unix symlinks. certbot renew refuses to touch a layout like this
    # ("expected cert.pem to be a symlink"), but nginx reads the PEM files
    # directly and doesn't care - so a still-valid cert is safe to use as-is.
    if openssl x509 -in "$CERT_FILE" -noout -checkend 604800 >/dev/null 2>&1; then
        echo "Certificate for ${NC_DOMAIN} is valid for at least 7 more days but not in certbot's symlink layout (likely restored from an archive) - skipping certbot."
        exit 0
    else
        echo "Certificate for ${NC_DOMAIN} is expiring soon and not in certbot's symlink layout - remove letsencrypt/live/${NC_DOMAIN} and re-run to request a fresh one." >&2
        exit 1
    fi
elif [ -d "letsencrypt/live/${NC_DOMAIN}" ]; then
    echo "Existing certificate found for ${NC_DOMAIN}, renewing..."
    docker run "${COMMON_ARGS[@]}" certbot/certbot:latest renew
else
    echo "No certificate yet for ${NC_DOMAIN}, requesting one (mode: ${MODE})..."
    docker run "${COMMON_ARGS[@]}" certbot/certbot:latest certonly \
        --manual \
        --preferred-challenges dns \
        --manual-auth-hook "sh /scripts/duckdns-auth.sh" \
        --manual-cleanup-hook "sh /scripts/duckdns-cleanup.sh" \
        -d "${NC_DOMAIN}" \
        --email "${LETSENCRYPT_EMAIL}" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        ${STAGING_FLAG}
fi
