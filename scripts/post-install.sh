#!/bin/bash
# Post-install occ maintenance - safe to re-run any number of times.
set -e
cd "$(dirname "$0")/.."
set -a; source .env; set +a

echo "Waiting for Nextcloud to finish its own install..."
for i in $(seq 1 30); do
    if docker exec nc_app php occ status 2>/dev/null | grep -q "installed: true"; then
        break
    fi
    sleep 5
done

docker exec nc_app php occ db:add-missing-indices
docker exec nc_app php occ db:convert-filecache-bigint -n
docker exec nc_app php occ config:system:set default_phone_region --value="LV"
docker exec nc_app php occ config:system:set maintenance_window_start --value="1" --type=integer
docker exec nc_app php occ background:cron
docker exec nc_app php occ maintenance:repair --include-expensive

if [ -n "${DESKTOP_USER:-}" ] && ! docker exec nc_app php occ user:list | grep -q "\- ${DESKTOP_USER}:"; then
    echo "Creating desktop sync user ${DESKTOP_USER}..."
    docker exec -e OC_PASS="${DESKTOP_USER_PASSWORD}" nc_app php occ user:add \
        --password-from-env --display-name="${DESKTOP_USER_DISPLAY_NAME}" "${DESKTOP_USER}"
else
    echo "Desktop sync user ${DESKTOP_USER} already exists, skipping."
fi
