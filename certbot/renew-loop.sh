#!/bin/sh
# Runs `certbot renew` once a day. certbot itself only actually renews
# when the cert is within its renewal window, so daily is safe/idempotent.
# On a real renewal, reloads nginx via the mounted Docker socket so the
# new cert is picked up without restarting the container.
set -eu

command -v docker >/dev/null 2>&1 || apk add --no-cache docker-cli >/dev/null

while true; do
    certbot renew --deploy-hook "docker exec nc_nginx nginx -s reload" || true
    sleep 86400
done
