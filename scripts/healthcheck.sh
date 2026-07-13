#!/bin/bash
# Quick smoke test after `make up` / `make deploy`.
set -u
cd "$(dirname "$0")/.."
set -a; source .env; set +a

echo "=== container status ==="
docker compose ps

echo
echo "=== healthchecks ==="
for c in nc_mariadb nc_redis nc_app; do
    status=$(docker inspect --format '{{.State.Health.Status}}' "$c" 2>/dev/null || echo "n/a")
    echo "  $c: $status"
done

echo
echo "=== HTTPS check ==="
CODE=$(curl -sS -o /dev/null -w "%{http_code}" "https://${NC_DOMAIN}/status.php")
echo "  https://${NC_DOMAIN}/status.php -> HTTP $CODE"
if [ "$CODE" != "200" ]; then
    echo "  [FAIL] expected 200"
    exit 1
fi

echo
echo "All good."
