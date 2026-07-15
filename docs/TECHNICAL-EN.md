# Nextcloud + MariaDB Deployment — Technical Documentation

Test assignment for Latvenergo System Engineer position. Reproducible Nextcloud
environment on Windows 11 + WSL2 + Docker Compose with a real, publicly-trusted
HTTPS certificate (Let's Encrypt, DNS-01 via DuckDNS).

Repository: https://github.com/kisshere69/nextcloud-latvenergo

---

## 1. Executive Summary

| # | Requirement | Status |
|---|------------|--------|
| 1 | Nextcloud + MariaDB running on local machine | ✅ |
| 2 | Real hostname, HTTPS certificate | ✅ (DuckDNS + Let's Encrypt DNS-01) |
| 3 | Desktop Client syncs without certificate warnings | ✅ (verified in production) |
| 4 | Administration → Overview without warnings | ✅ Almost clean — 4 intentional gaps explained in §9 |
| 5 | Successfully uploaded 2 GB file (md5sum verified) | ✅ (tested, md5 matches) |
| 6 | Environment reproducible from scratch with one command | ✅ (`make deploy`) |
| 7 | Monitoring / Logs / Auto-renewal | ✅ (all three implemented) |
| 8 | "What's missing for production" section | See §9 |
| 9 | Technical documentation | This document |
| 10 | Live offline demonstration | Certificate already issued and valid, works offline |

---

## 2. Architecture

```
Windows hosts file: 127.0.0.1  nextcloud-nikita.duckdns.org
        │
Nextcloud Desktop Client ──HTTPS (443)──┐
                                        │
WSL2 (Ubuntu 20.04) + Docker Compose    │
        ├── nginx           :443/:80 ◄──┘   (TLS termination, reverse proxy)
        ├── nextcloud (apache image)         (Nextcloud application)
        ├── cron                             (background jobs, same image)
        ├── mariadb                          (database)
        ├── redis                            (memcache + file locking)
        ├── certbot-renew                    (Let's Encrypt DNS-01 auto-renewal)
        └── monitoring:
              prometheus, node-exporter, cadvisor,
              mysqld-exporter, nginx-exporter,
              grafana (:3000), loki + promtail
```

**Why DNS-01 challenge (not HTTP-01):** Only requires TXT record changes in DNS,
no inbound port exposure required. A record can point anywhere — locally we resolve
to `127.0.0.1` via hosts file (both Windows and WSL).

---

## 3. Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| Docker Compose (not k8s) | Sufficient for single host, easily reproducible, understandable |
| DNS-01 challenge | No need for inbound access from internet, real certificate locally |
| DuckDNS | Free, supports TXT records via direct API update |
| Redis | Closes memcache/file locking warnings in Overview page |
| nginx as reverse proxy | TLS termination, security headers, streamed large file uploads |
| MariaDB 10.11 LTS | Officially recommended by Nextcloud |
| nextcloud:apache (not fpm) | Simpler nginx config (`proxy_pass`), not separate `fastcgi_pass` + shared volume |
| Prometheus + Grafana + Loki | Complete stack: metrics + logs in single interface |

---

## 4. Deployment from Scratch

```bash
# Preparation
cp .env.example .env
# Edit .env with real values

# Deploy
make bootstrap    # Verify prerequisites (WSL2, Docker, .env, hosts)
make certs        # Issue Let's Encrypt certificate (DNS-01)
make up           # Bring up entire stack
make post-install # Run occ commands: indices, cron, phone region, desktop user
make healthcheck  # Verify everything works

# Or all at once:
make deploy
```

**Prerequisites** (install once, Makefile doesn't automate these):
- Docker Desktop (WSL2 backend)
- `make` installed in WSL distro (`sudo apt-get install -y make`)
- DuckDNS account + token (free at https://duckdns.org)

**Real timing:** Full cycle `make nuke && make up && make post-install`
(delete data + deploy from scratch) takes ~40 seconds (images already cached locally).

---

## 5. TLS and Certificate Management

**Approach:** Let's Encrypt DNS-01 challenge via DuckDNS API

- `certbot/duckdns-auth.sh` / `duckdns-cleanup.sh` — Manual DNS-01 hooks,
  publish/cleanup TXT record via DuckDNS update API (`_acme-challenge.<domain>.duckdns.org`).
  
- `certbot/renew.sh` — Initial certificate issuance (staging → production).
  
- `certbot/renew-loop.sh` (container `certbot-renew`) — Runs daily check via
  `certbot renew`. If certificate approaching expiry, renews and runs `--deploy-hook`
  to reload nginx (`docker exec nc_nginx nginx -s reload`) via mounted Docker socket.

**Why DNS-01 for this setup:**
- ✅ No need to expose port 80 or 443 to the internet
- ✅ Works perfectly for local testing with real, publicly-trusted certificates
- ✅ Can be resolved locally via hosts file to 127.0.0.1
- ✅ Desktop client recognizes certificate as valid without warnings
- ✅ Same mechanism works in production (domain can be internal-only, just needs valid DNS)

**Certificate location:** `/etc/letsencrypt/live/<domain>/fullchain.pem` and `privkey.pem`
mounted into nginx container.

---

## 6. Security Configuration

**Secrets Management:**
- All passwords/tokens stored in `.env` file, which is in `.gitignore`
- Never committed to repository
- Loaded as environment variables at container startup

**Nextcloud User Account:**
- Desktop Client uses dedicated non-admin user (not `admin`) for daily sync
- Reduces blast radius if account compromised

**nginx TLS Configuration:**
- **TLS versions:** 1.2 and 1.3 only (no legacy 1.0/1.1)
- **Ciphers:** Modern, PFS-enabled cipher suite
- **Security headers:**
  - `Strict-Transport-Security: max-age=15768000` (HSTS, ~6 months)
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: SAMEORIGIN`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy: (restrictive)`
  
**Large file handling:**
- `client_max_body_size 0` (no limit)
- `proxy_request_buffering off` (stream directly to backend)
- Allows 2GB+ file uploads without intermediate buffering on nginx

**WebDAV routing:**
- `.well-known/carddav` and `.well-known/caldav` → `remote.php/dav`
- Required for CalDAV/CardDAV clients to discover endpoints behind reverse proxy

**Database access:**
- MariaDB user `nextcloud` has minimal privileges (only the database itself)
- Root password randomized and never used by application

---

## 7. Monitoring and Logging

**Prometheus** (`:9090`):
- Node Exporter — Host metrics (CPU, memory, disk, network)
- cAdvisor — Container metrics (CPU, memory, network per container)
- mysqld-exporter — MariaDB metrics (connections, query times, replication)
- nginx-exporter — nginx metrics (requests/sec, 4xx/5xx counts)

**Grafana** (`:3000`):
- Two pre-provisioned dashboards: "Host Overview" and "Containers"
- Auto-datasources via docker-compose volumes (no manual setup)
- Can add alerts for key metrics (cert expiry < 14 days, disk > 80%, services down)

**Loki + Promtail**:
- All container logs collected centrally
- Promtail uses Docker daemon socket with service discovery
- Logs accessible in Grafana Explore tab
- Correlation between metrics and logs for faster troubleshooting

**Key Metrics to Monitor:**
- Certificate expiry (days remaining)
- Disk space (main partition, database partition)
- MariaDB connections (should stay below `max_connections`)
- PHP-FPM idle/busy processes
- nginx 5xx error rate
- Nextcloud active users and storage usage

---

## 8. Known Limitations in This Environment

These limitations are specific to Windows + Docker Desktop + WSL2 and
**would NOT appear** on a "real" Linux Docker host:

**cAdvisor metrics per container limited:**
- Shows only aggregate Docker cgroup, not per-container breakdown
- Root cause: Docker Desktop uses containerd snapshotter (not classic overlay2 graphdriver),
  and cAdvisor cannot resolve container read-write layer ID in this setup
- Attempted: newer cAdvisor version + containerd.sock mount — no improvement
- **Impact:** Low — total container resource usage still visible, just not split by service

**node-exporter shows WSL2 VM metrics, not Windows host:**
- Docker Desktop containers run inside a Linux VM, not directly on Windows
- CPU/memory shown are VM totals, not physical Windows machine
- **Impact:** Medium — useful for capacity planning of WSL instance, but not Windows system

**Docker Desktop WSL integration can disconnect:**
- After `wsl --terminate`, Docker daemon may not auto-reconnect to Ubuntu-20.04
- Requires manual reset: Docker Desktop → Settings → Resources → WSL Integration → toggle off/on
- **Impact:** Low — rare, fixable in 30 seconds

---

## 9. What's Missing for Production

This setup is built for single-machine testing/demonstration. Real production
environment at Latvenergo would require:

### Communications & Notifications
- **Email server not configured** — No SMTP relay available in local environment
  - Production solution: Corporate SMTP server for password resets, notifications
  - Nextcloud setting: `mail_smtphost`, `mail_smtpport`, `mail_smtpauth`

### Access Control & Authentication
- **2FA not enforced** — Available but optional (doesn't clutter live demo)
  - Production: Require TOTP for all admins, offer to regular users
  - Integration: LDAP + TOTP, or Nextcloud Two-Factor (TOTP)
  
- **No SSO integration** — Local Nextcloud accounts only
  - Production: Active Directory / LDAP for domain-wide identity
  - Or SAML/OAuth if using external IdP

### Infrastructure Security
- **Docker socket mounted without restrictions** (`certbot-renew` container)
  - Current: Full Docker API access to renew certificates
  - Production: Use `docker-socket-proxy` with minimal policies
  - Only allow: `exec` to specific container, nothing else

### Data Protection
- **No backup strategy implemented**
  - Current: Data lost if Docker volume deleted
  - Production: Automated daily `mysqldump` + file backup to external storage (NAS / S3)
  - Test restore procedure weekly (backup without tested restore = no backup)
  - Define RPO (Recovery Point Objective, e.g., 1 day) and RTO (Recovery Time Objective, e.g., 4 hours)

### High Availability
- **Single node, no redundancy**
  - Current: Nextcloud, MariaDB, Redis all on one machine
  - Production requirements:
    - **Database:** MariaDB Galera Cluster (3+ nodes) or primary/replica replication with automatic failover
    - **Nextcloud:** Multiple app servers behind load balancer (stateless, except sessions via Redis)
    - **Redis:** Redis Sentinel or Cluster for cache failover
    - **File storage:** Network file system (NFS, Ceph) or S3 object storage (required for horizontal scaling)
    - **Load balancer:** HAProxy or cloud load balancer (AWS ALB, Azure LB)

### Monitoring & Operations
- **Grafana/Prometheus access unprotected**
  - Current: `localhost:3000` and `:9090`, only local access
  - Production: Behind reverse proxy with TLS + authentication (LDAP)
  - Or restricted to VPN/bastion host only

- **No alerting / on-call rotation**
  - Production: PagerDuty or OpsGenie integration
  - Define severity levels (P1: manual intervention needed immediately, P2: during business hours, P3: monitor, no alert)
  - Automatic escalation if not acknowledged within SLA

- **No runbooks for common incidents**
  - Production: Document typical issues (MariaDB full, Nextcloud stuck in maintenance, certificate expiry in 2 days)
  - Include troubleshooting steps and contact escalation

### Change Management & Deployment
- **No CI/CD pipeline**
  - Current: Manual `docker-compose up` and `occ` commands
  - Production: GitOps workflow
    - All config in Git (docker-compose.yml, nginx.conf, occ settings)
    - Staging environment mirrors production
    - Automated testing + security scanning before deploy
    - Blue-green or canary deployment with rollback capability

- **No automated patching**
  - Nextcloud updates: Manual `occ upgrade` or admin UI
  - OS patches: Manual WSL or manual Linux updates
  - Dependencies: Manual version bumps in docker-compose.yml
  - Production: Automated weekly patch Tuesday, with downtime window announced

### Compliance & Audit
- **No audit logging**
  - Production requirement for energy sector (NIS2 Directive):
    - Who logged in (when, from where)
    - Who accessed/modified/deleted files
    - Admin configuration changes
    - Failed login attempts
  - Solution: Enable Nextcloud Activity/Audit app, forward logs to SIEM

- **No data retention policy**
  - GDPR requirement: Define how long user data retained after account deletion
  - Implement: `occ dav:cleanup-direct-shares`, `files:cleanup` for retention

- **Sertifikāts un Secret Rotation**
  - Current: Certificate auto-renewal only, passwords never rotate
  - Production: Implement password rotation policy (90 days for DB, API tokens)
  - Tool: HashiCorp Vault or cloud secret manager (AWS Secrets Manager, Azure Key Vault)

### Performance & Capacity
- **No load testing performed**
  - Unknown: How many concurrent users before degradation?
  - Production: Baseline test (100, 500, 1000 users) with Apache JMeter
  - Identify bottleneck: PHP-FPM processes, DB connections, Redis, disk I/O?

- **No capacity planning**
  - Current: Storage assumed infinite
  - Production: Monitor daily growth rate, predict disk full date
  - Reserve space for: database snapshots, transaction logs, temporary files

---

## 10. Testing & Validation Checklist

### Large File Upload (2 GB)
```bash
# Generate test file
dd if=/dev/urandom of=test-2gb.bin bs=1M count=2048

# Upload (via web UI or desktop client)
md5sum test-2gb.bin           # e.g., abc123...
# ... upload to Nextcloud ...
# Download back
md5sum downloaded-file        # Must match abc123...
```
- ✅ File successfully persisted in MariaDB
- ✅ No truncation, no corruption
- ✅ Desktop Client can sync large files

### Desktop Client Certificate Validation
```bash
# Windows: add to C:\Windows\System32\drivers\etc\hosts
127.0.0.1  nextcloud-nikita.duckdns.org

# In Nextcloud Desktop Client:
# Connect to: https://nextcloud-nikita.duckdns.org
# ✅ NO certificate warning dialog
# ✅ Desktop Client shows "Connected" immediately
# ✅ File sync starts automatically
```

### Administration Overview Security Checks
Navigate to Administration → Overview:

**Issues addressed in this setup:**
- ✅ Memcache for file locking (Redis configured)
- ✅ No PHP OPcache issue (disabled, can be re-enabled safely)
- ✅ All mandatory security headers present
- ✅ HTTPS enforced + HSTS header
- ✅ `default_phone_region` set to `LV`
- ✅ Background jobs running (cron container executes `occ background:cron` every 5 min)
- ✅ Database indices optimized

**Known remaining items (explained in §9):**
- ⚠️ Email not configured (no SMTP)
- ⚠️ 2FA not mandatory (available, not enforced)
- ⚠️ Some optional Nextcloud modules not installed
- ⚠️ Server ID blank (multi-server deployments only)

---

## 11. Quick Troubleshooting Guide

### Certificate rejected by browser/client

**Symptom:** "Certificate not trusted" error even though HTTPS works.

**Root causes:**
1. `TECHNICAL.md` shows `cert.pem` in nginx config instead of `fullchain.pem`
   - Fix: nginx.conf must reference `fullchain.pem`
   - `fullchain.pem` includes root CA chain, `cert.pem` alone does not
   
2. Hosts file not updated on Windows
   - Verify: `type C:\Windows\System32\drivers\etc\hosts` contains `127.0.0.1  nextcloud-nikita.duckdns.org`
   - DNS leakage: `nslookup nextcloud-nikita.duckdns.org` should show 127.0.0.1

3. WSL hosts file not updated
   - Inside WSL: `cat /etc/hosts` should contain `127.0.0.1  nextcloud-nikita.duckdns.org`

### nginx 502 Bad Gateway

**Symptom:** `https://nextcloud-nikita.duckdns.org` returns 502 error.

**Check:** 
```bash
docker logs nc_nginx     # Look for connection refused
docker logs nc_nextcloud # Is Nextcloud up? Any errors?
docker ps                # Is nextcloud container running?
```

**Common fixes:**
1. Nextcloud container not ready → wait 30 seconds, refresh
2. PHP-FPM port 9000 not open between nginx and nextcloud
   - Both must be on same Docker network
   - Verify: docker-compose.yml has both in same `networks:` section

### Certbot certificate renewal fails

**Symptom:** 
```
Error: acme: urn:acme:error:dns: DNS problem: NXDOMAIN looking up _acme-challenge.nextcloud-nikita.duckdns.org
```

**Root causes:**
1. DuckDNS token invalid or expired
   - Regenerate: https://duckdns.org, update `.env` file
   
2. DNS propagation delay
   - `certbot/renew.sh` uses `--dns-duckdns-propagation-seconds 60` to allow 60s for TXT record
   - For DuckDNS, 60 seconds usually enough
   
3. Rate limit hit
   - If getting 429 errors, you've issued >50 certificates on this domain in a week
   - Solution: Wait 7 days, or use different domain for testing
   - Use `--staging` flag during development (`--staging` certs have no limit)

**Verify manually:**
```bash
# Inside WSL container that has dig/nslookup
docker exec -it nc_nginx bash
nslookup _acme-challenge.nextcloud-nikita.duckdns.org
# Should show the TXT record value
```

### MariaDB "Too many connections" error

**Symptom:** Nextcloud shows database error, logs show "User 'nextcloud'@'127.0.0.1': Access denied".

**Fix:**
```bash
docker exec nc_mariadb mysql -u root -p$MARIADB_ROOT_PASSWORD -e \
  "SET GLOBAL max_connections = 1000; SHOW VARIABLES LIKE 'max_connections';"
```

Persist in docker-compose.yml:
```yaml
mariadb:
  command: --max-connections=1000 --max_allowed_packet=1G
```

### Desktop Client stuck on "Checking for changes"

**Symptom:** Sync doesn't progress, CPU at 0%, network idle.

**Check:**
```bash
# Tail Nextcloud logs
docker logs nc_nextcloud | grep -i sync

# Check if WebDAV is responding
curl -u testuser:password https://nextcloud-nikita.duckdns.org/remote.php/dav/files/testuser/ \
  --insecure  # Use this only for debugging!
```

**Fixes:**
1. Restart Nextcloud container: `docker compose restart nc_nextcloud`
2. Disable/re-enable sync folder in desktop client
3. Increase PHP timeout in docker-compose.yml: `PHP_MEMORY_LIMIT=1G`, `PHP_MAX_EXECUTION_TIME=3600`

---

## 12. Performance Tuning Parameters

### MariaDB Configuration
```yaml
mariadb:
  environment:
    MYSQL_MAX_ALLOWED_PACKET: "1G"          # Allows large queries
    MARIADB_INNODB_BUFFER_POOL_SIZE: "512M" # ~50-70% of available RAM
    MARIADB_INNODB_LOG_FILE_SIZE: "100M"    # For write-heavy workloads
```

### PHP Configuration (via Apache)
```dockerfile
# In nextcloud Dockerfile or docker-compose ENV:
PHP_MEMORY_LIMIT: "1G"              # Nextcloud indexing, video processing
PHP_UPLOAD_MAX_FILESIZE: "2G"       # Limit on file uploads
PHP_MAX_INPUT_TIME: "3600"          # Large file timeout
PHP_POST_MAX_SIZE: "2G"             # POST body size limit
PHP_MAX_EXECUTION_TIME: "3600"      # Script timeout (1 hour for 2GB uploads)
```

### nginx Configuration
```nginx
# In nginx.conf:
proxy_connect_timeout 60s;          # Connect timeout
proxy_send_timeout 600s;            # Time waiting for upstream write
proxy_read_timeout 600s;            # Time waiting for upstream read
client_body_timeout 600s;           # Time waiting for request body
client_header_timeout 60s;          # Time waiting for request header
```

---

## 13. Maintenance Tasks

### Daily
- Check Grafana dashboards for anomalies (disk, memory, database connections)
- Review error logs: `docker logs nc_nextcloud | grep -i error | tail -20`

### Weekly
- Test certificate renewal: `docker exec nc_certbot certbot renew --dry-run`
- Verify backup completion (if implemented)
- Check for Nextcloud security updates: Administration → Apps → Updates

### Monthly
- Full backup test: Take backup, verify restore procedure works
- Capacity review: Disk usage growth, database size
- Security audit: Failed login attempts, suspicious activity

### Quarterly
- Performance review: Peak user load, identify bottlenecks
- Dependency updates: MariaDB, PHP minor versions, container base images
- Documentation update: Record any changes, known issues, new workarounds

---

## 14. References & Links

**Official Documentation:**
- Nextcloud Admin Manual: https://docs.nextcloud.com/server/latest/admin_manual/
- Nextcloud Security Hardening: https://docs.nextcloud.com/server/latest/admin_manual/installation/harden_nextcloud.html
- MariaDB Official: https://mariadb.com/kb/en/
- Let's Encrypt: https://letsencrypt.org/docs/
- DuckDNS API: https://duckdns.org/install

**Tools:**
- Docker Compose: https://docs.docker.com/compose/
- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/
- Loki: https://grafana.com/docs/loki/latest/

**This Deployment:**
- Repository: https://github.com/kisshere69/nextcloud-latvenergo
- Issue Tracker: [GitHub Issues]
- For questions: [Contact details]

---

## Appendix A: Environment Variables (.env.example)

```bash
# DuckDNS Configuration
DUCKDNS_DOMAIN=nextcloud-nikita
DUCKDNS_TOKEN=<your-duckdns-token>
NC_DOMAIN=nextcloud-nikita.duckdns.org

# Nextcloud Admin
NC_ADMIN_USER=admin
NC_ADMIN_PASSWORD=<strong-password>

# MariaDB
MARIADB_ROOT_PASSWORD=<strong-root-password>
MARIADB_PASSWORD=<strong-nextcloud-db-password>
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud

# Redis
REDIS_PASSWORD=<strong-redis-password>

# TZ (timezone)
TZ=Europe/Riga

# Debug (optional)
DEBUG=false
```

---

## Appendix B: Useful occ Commands

```bash
# Database maintenance
docker exec -u www-data nc_nextcloud php occ db:add-missing-indices
docker exec -u www-data nc_nextcloud php occ db:add-missing-columns
docker exec -u www-data nc_nextcloud php occ db:add-missing-primary-keys
docker exec -u www-data nc_nextcloud php occ db:convert-filecache-bigint

# Background jobs
docker exec -u www-data nc_nextcloud php occ background:cron

# User management
docker exec -u www-data nc_nextcloud php occ user:create testuser
docker exec -u www-data nc_nextcloud php occ user:delete testuser

# Config
docker exec -u www-data nc_nextcloud php occ config:system:get default_phone_region
docker exec -u www-data nc_nextcloud php occ config:system:set default_phone_region --value="LV"

# Maintenance
docker exec -u www-data nc_nextcloud php occ maintenance:mode --off
docker exec -u www-data nc_nextcloud php occ upgrade

# Health check
docker exec nc_nextcloud php occ status
docker exec nc_nextcloud php occ check
```

---

**Document Version:** 1.0  
**Last Updated:** July 2026  
**Author:** Nikita Kiss (Vendetta)  
**Status:** Production-Ready Demo Environment
