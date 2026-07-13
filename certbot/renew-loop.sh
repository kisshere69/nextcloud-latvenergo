#!/bin/sh

set -eu

command -v docker >/dev/null 2>&1 || apk add --no-cache docker-cli >/dev/null

while true; do
    certbot renew --deploy-hook "docker exec nc_nginx nginx -s reload" || true
    sleep 86400
done
