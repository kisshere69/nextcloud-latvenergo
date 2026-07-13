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

if [ -d "letsencrypt/live/${NC_DOMAIN}" ]; then
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
