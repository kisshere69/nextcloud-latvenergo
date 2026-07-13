#!/bin/sh

# clear the DNS-01 TXT challenge from DuckDNS.
set -eu

command -v curl >/dev/null 2>&1 || apk add --no-cache curl >/dev/null

SUBDOMAIN="${NC_DOMAIN%.duckdns.org}"

curl -fsS "https://www.duckdns.org/update?domains=${SUBDOMAIN}&token=${DUCKDNS_TOKEN}&txt=removed&clear=true" >/dev/null || true
