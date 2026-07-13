.PHONY: bootstrap certs-staging certs up post-install healthcheck down nuke deploy logs status

# Check prerequisites (WSL2, Docker, .env, hosts) before deploying
bootstrap:
	bash scripts/bootstrap.sh

# Issue/renew a Let's Encrypt STAGING certificate (no rate limits, for testing the DNS-01 flow)
certs-staging:
	bash certbot/renew.sh staging

# Issue/renew the real Let's Encrypt PROD certificate
certs:
	bash certbot/renew.sh prod

# Start the whole stack
up:
	docker compose up -d

# Post-install occ maintenance (indices, bigint, cron, phone region...) - safe to re-run
post-install:
	bash scripts/post-install.sh

# Smoke test: containers healthy + HTTPS responds
healthcheck:
	bash scripts/healthcheck.sh

# Stop containers, keep data
down:
	docker compose down

# Stop containers AND wipe all data volumes - full reset
nuke:
	docker compose down -v

# One command, from scratch: check deps -> cert -> start -> configure -> verify
deploy: bootstrap certs up post-install healthcheck
	@echo "Deployed: https://$$(grep ^NC_DOMAIN .env | cut -d= -f2)"

logs:
	docker compose logs -f

status:
	docker compose ps
