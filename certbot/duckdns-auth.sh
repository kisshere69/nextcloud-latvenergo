#!/bin/sh

set -eu

command -v curl >/dev/null 2>&1 || apk add --no-cache curl >/dev/null

SUBDOMAIN="${NC_DOMAIN%.duckdns.org}"

RESPONSE=$(curl -fsS "https://www.duckdns.org/update?domains=${SUBDOMAIN}&token=${DUCKDNS_TOKEN}&txt=${CERTBOT_VALIDATION}")
if [ "$RESPONSE" != "OK" ]; then
    echo "DuckDNS TXT update failed: $RESPONSE" >&2
    exit 1
fi

echo "TXT record published for _acme-challenge.${NC_DOMAIN}, waiting for DNS propagation..."
sleep 30