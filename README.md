# Nextcloud + MariaDB — Latvenergo Homework

Reproducible Nextcloud deployment on Windows 11 + WSL2 + Docker Compose with real HTTPS (Let's Encrypt DNS-01 via DuckDNS).

## Stack

| Component | Role |
|-----------|------|
| nginx | Reverse proxy, TLS termination |
| nextcloud | Application (php-fpm) |
| mariadb | Database |
| redis | Cache + file locking |
| certbot | Let's Encrypt DNS-01 renewal |
| prometheus + grafana | Metrics & dashboards |
| loki + promtail | Log aggregation |

## Quick Start

```bash
cp .env.example .env
# Edit .env with the DuckDNS domain and token

make bootstrap   # check dependencies, prepare env
make certs       # issue Let's Encrypt certificate
make up          # start all services
make post-install # run occ commands (indices, cron, phone region...)
```

## Requirements

- Windows 11 with WSL2
- Docker Desktop (WSL2 backend)
- DuckDNS account + subdomain

## Documentation

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for full technical documentation.
