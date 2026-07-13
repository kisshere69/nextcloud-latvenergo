# Nextcloud + MariaDB — Latvenergo Homework

Reproducible Nextcloud deployment on Windows 11 + WSL2 + Docker Compose with real HTTPS (Let's Encrypt DNS-01 via DuckDNS).

## Stack

| Component | Role |
|-----------|------|
| nginx | Reverse proxy, TLS termination |
| nextcloud | Application (apache) |
| cron | Nextcloud background jobs (same image, `/cron.sh`) |
| mariadb | Database |
| redis | Cache + file locking |
| certbot-renew | Daily Let's Encrypt DNS-01 renewal check |
| prometheus + node-exporter + cadvisor + mysqld-exporter + nginx-exporter | Metrics |
| grafana | Dashboards (provisioned automatically) |
| loki + promtail | Log aggregation |

## Quick Start

```bash
cp .env.example .env
# Edit .env with the DuckDNS domain and token

make bootstrap   # check dependencies, prepare env
make certs       # issue Let's Encrypt certificate
make up          # start all services
make post-install # run occ commands (indices, cron, phone region...)
make healthcheck # verify everything is up
```

Or all of the above in one shot: `make deploy`.

- Nextcloud: `https://<your-domain>`
- Grafana: `http://localhost:3000` (datasources + dashboards provisioned automatically)
- Prometheus: `http://localhost:9090`

## Requirements

- Windows 11 with WSL2
- Docker Desktop (WSL2 backend)
- `make` inside the WSL distro (`sudo apt-get install -y make`) - not preinstalled on a fresh Ubuntu
- DuckDNS account + subdomain

## Documentation

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for full technical documentation.
