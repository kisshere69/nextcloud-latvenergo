# Nextcloud + MariaDB izvietošana — tehniskā dokumentācija

Testa uzdevums Latvenergo System Engineer amatam. Reproducējama Nextcloud
vide uz Windows 11 + WSL2 + Docker Compose ar reālu, publiski uzticamu
HTTPS sertifikātu (Let's Encrypt, DNS-01 caur DuckDNS).

Repozitorijs: https://github.com/kisshere69/nextcloud-latvenergo

---

## 1. Pārskats

| # | Prasība | Statuss |
|---|---------|---------|
| 1 | Nextcloud + MariaDB uz lokālā datora | ✅ |
| 2 | Reāls hostname, HTTPS | ✅ (DuckDNS + Let's Encrypt DNS-01) |
| 3 | Desktop Client sinhronizē bez sertifikāta brīdinājumiem | ✅ (pārbaudīts reāli) |
| 4 | Administration → Overview bez brīdinājumiem | Gandrīz tīrs — 4 apzināti neaizvērti punkti, skat. §9 |
| 5 | Veiksmīgi augšupielādēts 2 GB fails (md5sum) | ✅ (pārbaudīts, md5 sakrīt) |
| 6 | Vide atjaunojama no nulles ar vienu komandu | ✅ (`make deploy`) |
| 7 | Monitorings / logi / auto-renewal | ✅ (visi trīs) |
| 8 | "Kas trūkst produkcijai" sadaļa | Skat. §9 |
| 9 | Tehniskā dokumentācija | Šis dokuments |
| 10 | Klātienes demonstrācija bezsaistē | Sertifikāts jau izsniegts un derīgs, darbojas bez interneta |

---

## 2. Arhitektūra

```
Windows hosts fails: 127.0.0.1  <domēns>.duckdns.org
        │
Nextcloud Desktop Client ──HTTPS (443)──┐
                                        │
WSL2 (Ubuntu 20.04) + Docker Compose    │
        ├── nginx           :443/:80 ◄──┘   (TLS termination, reverse proxy)
        ├── nextcloud (apache image)         (Nextcloud aplikācija)
        ├── cron                             (background jobs, tas pats image)
        ├── mariadb                          (datubāze)
        ├── redis                            (memcache + file locking)
        ├── certbot-renew                    (Let's Encrypt DNS-01 auto-renewal)
        └── monitoring:
              prometheus, node-exporter, cadvisor,
              mysqld-exporter, nginx-exporter,
              grafana (:3000), loki + promtail
```

**Kāpēc DNS-01 izaicinājums (nevis HTTP-01):** vajadzīga tikai TXT ieraksta
maiņa DNS, nav jāatver neviens ports uz āru. A-ieraksts var norādīt uz
jebkuru IP — lokāli to atrisinām uz `127.0.0.1` caur hosts failu (Windows
un WSL abās pusēs).

---

## 3. Galvenie tehniskie lēmumi

| Lēmums | Pamatojums |
|--------|-----------|
| Docker Compose (nevis k8s) | Pietiek vienam hostam, viegli reproducējams, saprotams |
| DNS-01 izaicinājums | Nav vajadzīga ienākošā piekļuve no interneta, reāls sertifikāts lokāli |
| DuckDNS | Bezmaksas, atbalsta TXT ierakstus tieši caur update API |
| Redis | Aizver memcache/file locking brīdinājumus Overview lapā |
| nginx kā reverse proxy | TLS termination, drošības headeri, straumēta liela faila augšupielāde |
| MariaDB 10.11 LTS | Oficiāli rekomendēts Nextcloud |
| nextcloud:apache (nevis fpm) | Vienkāršāks nginx konfigs (`proxy_pass`), nevis `fastcgi_pass` + koplietots volume |
| Prometheus + Grafana + Loki | Pilns steks: metrikas + logi vienā interfeisā |

---

## 4. Izvietošana no jauna

```bash
cp .env.example .env
# aizpilda reālas vērtības .env failā

make bootstrap    # pārbauda priekšnosacījumus (WSL2, Docker, .env, hosts)
make certs        # izsniedz Let's Encrypt sertifikātu (DNS-01)
make up           # paceļ visu steku
make post-install # occ komandas: indeksi, cron, phone region, desktop lietotājs
make healthcheck  # pārbauda, ka viss strādā

# vai viss uzreiz:
make deploy
```

Priekšnosacījumi (jāinstalē vienreiz, Makefile to nedara automātiski):
Docker Desktop (WSL2 backend), `make` iekš WSL distro
(`sudo apt-get install -y make`).

**Reāli pārbaudīts:** pilns cikls `make nuke && make up && make post-install`
(datu dzēšana + izvietošana no nulles) aizņem ~40 sekundes (attēli jau
lokāli kešoti).

---

## 5. TLS un sertifikāti

- `certbot/duckdns-auth.sh` / `duckdns-cleanup.sh` — manual DNS-01 hooks,
  publicē/notīra TXT ierakstu caur DuckDNS update API
  (`_acme-challenge.<domēns>.duckdns.org`).
- `certbot/renew.sh` — pirmā sertifikāta izsniegšana (staging → prod).
- `certbot/renew-loop.sh` (konteiners `certbot-renew`) — reizi diennaktī
  pārbauda `certbot renew`; ja sertifikāts tuvojas termiņam, atjauno un
  ar `--deploy-hook` restartē nginx (`docker exec nc_nginx nginx -s
  reload`) caur samontēto Docker socket.

---

## 6. Drošība

- Nextcloud Desktop Client izmanto atsevišķu, ne-administratora
  lietotāju (nevis `admin`) ikdienas sinhronizācijai.
- nginx: HSTS (`max-age=15768000`), `client_max_body_size 0` +
  `proxy_request_buffering off` lieliem failiem, `.well-known/carddav`
  un `/caldav` pāradresācija tieši uz HTTPS (Apache pati to nezinātu
  darīt pareizi aiz reverse proxy).
- Visi paroles/tokeni tiek glabāti `.env` failā, kas ir `.gitignore`
  sarakstā — repozitorijā nekad netiek commitoti.
- `mysqld-exporter` parole netiek glabāta failā repozitorijā — tā tiek
  ģenerēta konteinera startēšanas brīdī no `.env` mainīgā.

---

## 7. Monitorings un logi

- **Prometheus** (`:9090`) — node-exporter (hosts), cAdvisor (konteineri),
  mysqld-exporter (MariaDB), nginx-exporter (`stub_status` uz iekšēja
  porta, nav publicēts uz āru).
- **Grafana** (`:3000`) — datasources un divi dashboardi (Host Overview,
  Containers) tiek automātiski provisionēti caur docker-compose volumes,
  nav manuāli jāiestata.
- **Loki + Promtail** — visu konteineru logi (docker service discovery
  caur Docker socket), pieejami Grafana Explore.

---

## 8. Zināmie ierobežojumi šajā vidē

Šie ierobežojumi ir specifiski Windows + Docker Desktop + WSL2 videi un
**neparādītos** uz "īsta" Linux Docker hosta:

- **cAdvisor nerāda metrikas pa atsevišķiem konteineriem** — tikai
  kopējo Docker cgroup summu. Iemesls: Docker Desktop izmanto containerd
  snapshotter, nevis klasisko overlay2 graphdriver, un cAdvisor (arī
  jaunākā versija) nevar atrisināt konteinera read-write layer ID šajā
  shēmā. Mēģināts: jaunāka cAdvisor versija + containerd.sock mounts —
  nepalīdzēja.
- **node-exporter rāda WSL2 iekšējās VM metrikas**, nevis fizisko
  Windows hostu — Docker Desktop konteineri darbojas iekšējā Linux VM,
  nevis tieši uz Windows.
- **Docker Desktop WSL integrācija ar Ubuntu-20.04 periodiski
  atslēdzas** pēc `wsl --terminate` — jāieslēdz atpakaļ manuāli
  (Docker Desktop → Settings → Resources → WSL Integration).

---

## 9. Kas trūkst produkcijas videi

Šis stends ir veidots vienam demonstrācijas/testa mērķim uz vienas
mašīnas. Reālā produkcijas vidē trūkst/būtu jāmaina:

- **E-pasta serveris nav konfigurēts** — nav pieejama SMTP relejs
  lokālajā vidē. Produkcijā izmantotu uzņēmuma SMTP serveri
  paziņojumiem un lietotāju atgūšanai.
- **Divfaktoru autentifikācija (2FA) nav piespiedu kārtā ieslēgta** —
  pieejama, bet neobligāta, lai neapgrūtinātu dzīvo demonstrāciju.
  Produkcijā būtu jāpiespiedu ieslēdz vismaz administratoriem.
- **`docker.sock` tiek montēts `certbot-renew` konteinerā** bez
  ierobežojumiem — dod pilnu piekļuvi Docker API. Produkcijā
  jāizmanto ierobežots `docker-socket-proxy` ar minimālām tiesībām
  (tikai `exec` uz konkrētu konteineri).
- **Nav backup stratēģijas** — datubāzes un failu dublēšana uz ārēju
  glabātuvi (piem., citu serveri vai object storage) šeit nav
  ieviesta.
- **Viens serveris, nav augstas pieejamības (HA)** — MariaDB, Redis,
  Nextcloud viss uz viena hosta. Produkcijā — vismaz DB replikācija,
  vairāki app serveri aiz load balancera.
- **Server ID nav konfigurēts** — aktuāli tikai vairāku PHP serveru
  gadījumā (skat. Overview brīdinājumu), šeit nav pielietojams.
- **AppAPI deploy daemon nav konfigurēts** — nav nepieciešams, jo
  netiek izmantotas External Apps (ExApps).
- **Monitoringa/Grafana piekļuve nav aiz autentifikācijas/reverse
  proxy ar TLS** — pieejama tikai lokāli (`localhost:3000/:9090`).
  Produkcijā — aiz VPN vai atsevišķa autentificēta reverse proxy.
- **Sertifikātu un atslēgu rotācija** — MariaDB/Redis paroles šobrīd
  nekad nemainās automātiski; produkcijā vajadzētu paroļu rotācijas
  procesu (piem., ar Vault).

---

## 10. Testēšana

- **2 GB augšupielāde:** WebDAV PUT/GET (`remote.php/dav/files/...`),
  md5sum pirms un pēc — identisks. Testa fails glabājas lokāli
  (`test-2gb.bin`, git ignorēts) atkārtotai augšupielādei klātienē.
- **Desktop Client:** pieslēgšanās bez ne viena sertifikāta
  brīdinājuma, sinhronizācija strādā.
- **Administration → Overview:** visi standarta brīdinājumi aizvērti
  (`occ db:add-missing-indices`, `db:convert-filecache-bigint`,
  `default_phone_region`, `maintenance_window_start`, cron režīms,
  HSTS header). Atlikušie 4 punkti — skat. §9 iemeslus.

Detalizēts problēmu un risinājumu žurnāls: [`docs/NOTES.md`](NOTES.md).
