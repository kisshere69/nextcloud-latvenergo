# Nextcloud + MariaDB — Latvenergo System Engineer Homework

## Контекст

**Цель:** Тестовое задание для Latvenergo на должность System Engineer.
**Стек:** Windows 11 + WSL2 (Ubuntu) + Docker Compose
**Дата начала:** 2026-07-13
**Оригинальный файл задания:** `C:\Users\nikit\Downloads\homework-is-inz-2026.docx` (на латышском)
**Детальный план:** `C:\Users\nikit\Downloads\latvenergo-nextcloud-plan.md`

---

## Требования из задания (оригинал: латышский)

1. Nextcloud + MariaDB запущены на локальном компьютере
2. Установлено на **реальном hostname**, доступно через **HTTPS**
3. Nextcloud Desktop Client синхронизирует файлы **без предупреждений о сертификате**
   - Запрещено: `-k`, `insecure`, `skip-verify`, самоподписанный CA в доверенных
4. `Administration → Overview` — **без предупреждений**
   - Если варнинг не закрыт — задокументировать: почему, что пробовал, где остановился
5. Успешно загружен файл **2 GB** (проверка md5sum)
6. Среда **воспроизводится с нуля** одной командой (Makefile / скрипт)
7. **Мониторинг** и/или сбор логов и/или авто-renewal сертификатов
8. Раздел «**чего не хватает для продакшена**»
9. Короткая **техническая документация** (латышский или английский)
10. На встречу принести ноутбук — **демонстрация живьём**, всё работает офлайн

---

## Архитектура (целевая)

```
Windows host
  └── hosts file: 127.0.0.1  nextcloud-<name>.duckdns.org
  └── Nextcloud Desktop Client ──HTTPS──┐
                                        │
WSL2 (Ubuntu)                           │
  └── Docker Compose                    │
        ├── nginx (TLS termination)   :443 ◄─┘
        ├── nextcloud (apache, образ nextcloud:apache)
        ├── mariadb
        ├── redis (memcache + file locking)
        ├── certbot (DNS-01 renewal)
        └── monitoring: prometheus + node-exporter + grafana + loki + promtail

Volumes: nc_data, nc_config, db_data, certs, letsencrypt
```

**Почему DNS-01 (Let's Encrypt):** TXT-запись в DNS, не нужно открывать порты наружу.
A-запись может смотреть куда угодно. Локально резолвим в 127.0.0.1 через hosts.
Итог: настоящий публично доверенный сертификат, клиент проверяет полноценно.

---

## Список задач (порядок выполнения)

| Задача | Описание | Статус |
|--------|----------|--------|
| 0 | Подготовка: WSL2, Docker, скелет репо | [x] |
| 1 | Hostname: DuckDNS + hosts (Windows + WSL) | [x] |
| 2 | TLS: Let's Encrypt DNS-01 (staging → prod) | [x] |
| 3 | MariaDB: utf8mb4, InnoDB параметры, healthcheck | [x] |
| 4 | Nextcloud + Redis | [x] |
| 5 | nginx: TLS termination, security headers, redirects | [x] |
| 6 | Чистый Overview: все occ-команды | [x] |
| 7 | Загрузка 2 GB файла, md5 проверка | [x] |
| 8 | Desktop Client: синк без предупреждений | [x] |
| 9 | Воспроизводимость: Makefile, bootstrap.sh | [ ] |
| 10 | Мониторинг: Prometheus + Grafana + Loki, certbot renewal | [ ] |
| 11 | Техдокументация (docs/TECHNICAL.md) | [ ] |
| 12 | Раздел «для продакшена» | [ ] |

**Критический путь:** 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8, параллельно: 9, 10, потом 11, 12

---

## Структура репозитория

```
nextcloud-latvenergo/
├── CONTEXT.md              ← этот файл (контекст для Claude)
├── docker-compose.yml
├── .env.example
├── .env                    ← в .gitignore!
├── .gitignore
├── Makefile
├── nginx/
│   └── nextcloud.conf
├── certbot/
│   └── renew.sh
├── monitoring/
│   ├── prometheus.yml
│   └── promtail.yml
├── scripts/
│   ├── bootstrap.sh
│   └── healthcheck.sh
└── docs/
    ├── TECHNICAL.md        ← финальная техдокументация (латышский/англ.)
    └── NOTES.md            ← рабочие заметки: ошибки, решения, наблюдения
```

---

## Ключевые технические решения (с обоснованием)

| Решение | Почему |
|---------|--------|
| Docker Compose (не k8s) | Достаточно для одного хоста, воспроизводимо, понятно |
| DNS-01 challenge | Не нужен внешний доступ, реальный сертификат локально |
| DuckDNS | Бесплатный, есть certbot-плагин, поддерживает TXT-записи |
| Redis | Закрывает варнинги memcache + file locking в Overview |
| nginx как reverse proxy | TLS termination, security headers, upload buffering |
| MariaDB 10.11 LTS | Официально рекомендован Nextcloud |
| nextcloud:apache (не fpm) | nginx делает простой proxy_pass на порт 80, без fastcgi_params — меньше хрупких мест в конфиге |
| Prometheus + Grafana + Loki | Полный стек: метрики + логи в одном интерфейсе |

---

## Типовые варнинги Overview и как закрываются

| Варнинг | Решение |
|---------|---------|
| Memcache/file locking | Redis + config.php |
| Security headers | nginx конфиг |
| .well-known/carddav, caldav | nginx redirect → /remote.php/dav |
| HSTS | nginx: Strict-Transport-Security |
| PHP OPcache | php.ini: interned_strings_buffer, max_accelerated_files |
| PHP модули (imagick, bcmath) | В Dockerfile/образе |
| Cron не настроен | occ background:cron + системный cron |
| Индексы БД | occ db:add-missing-indices |
| BigInt конвертация | occ db:convert-filecache-bigint |
| maintenance_window_start | occ config:system:set |
| default_phone_region | occ config:system:set --value="LV" |

---

## Переменные окружения (.env)

```
NC_DOMAIN=nextcloud-<name>.duckdns.org
DUCKDNS_TOKEN=<token>
MYSQL_ROOT_PASSWORD=<secret>
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=<secret>
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=<secret>
REDIS_HOST=redis
```

---

## Чек-лист перед встречей

- [ ] Всё работает после перезагрузки ноута (restart: unless-stopped)
- [ ] Полный цикл `make nuke && make up` прогнан и засечено время
- [ ] Скриншот чистого Overview
- [ ] Скриншот Desktop Client «Synchronized»
- [ ] Скриншот Grafana dashboard
- [ ] Тестовый 2 GB файл готов к загрузке вживую
- [ ] Уметь объяснить каждую строчку docker-compose.yml и nginx.conf
- [ ] Подготовить ответы: «почему не X?» для каждого решения
- [ ] Offline: сертификат уже выпущен и валиден без интернета

---

## Инструкция для Claude (новая сессия)

При старте новой сессии скажи: "посмотри CONTEXT.md"
Путь к файлу: `C:\Users\nikit\nextcloud-latvenergo\CONTEXT.md`

Текущий статус: Задачи 0-8 готовы.
- WSL2 2.7.10 + Ubuntu 20.04.6 LTS, Docker Desktop 4.80.0 (Engine 29.6.1,
  Compose v5.3.0), WSL-интеграция с Ubuntu-20.04 включена и проверена.
  Диск 955G своб., память 13G своб.
- GitHub-репо создан и запушен: https://github.com/kisshere69/nextcloud-latvenergo
- DuckDNS: nextcloud-nikita.duckdns.org (A-запись → 83.99.212.156).
  .env заполнен (домен, DuckDNS token, сгенерированные пароли, email).
  hosts (Windows + WSL Ubuntu-20.04) → 127.0.0.1, резолвинг проверен.
- TLS: certbot/duckdns-auth.sh + duckdns-cleanup.sh (manual DNS-01 hooks,
  используют DuckDNS update API с txt=). certbot/renew.sh оборачивает
  certonly/renew в docker run. Makefile: certs-staging, certs.
  Реальный prod-сертификат выпущен и лежит в ./letsencrypt/ (gitignored):
  issuer=Let's Encrypt, subject=nextcloud-nikita.duckdns.org,
  истекает 2026-10-11.
  ВАЖНО (грабли на будущее): Docker Desktop WSL-интеграция с Ubuntu-20.04
  периодически слетает после wsl --terminate/перезапуска — приходится
  заново включать тумблер в Docker Desktop → Settings → Resources → WSL
  Integration. Также ~/.docker/config.json в WSL был вручную очищен
  (credsStore: desktop.exe вызывал "exec format error" при docker pull) —
  если Docker Desktop пересоздаст этот файл, ту же ошибку придётся чинить
  так же (заменить содержимое на {}).
- MariaDB: docker-compose.yml с сервисом mariadb:10.11. Настройки под
  Nextcloud: transaction-isolation=READ-COMMITTED, binlog-format=ROW,
  innodb-file-per-table=1, character-set-server=utf8mb4,
  collation-server=utf8mb4_general_ci, max-allowed-packet=128M,
  innodb-buffer-pool-size=1G. Healthcheck — встроенный в образ
  healthcheck.sh (--connect --innodb_initialized). Поднято и проверено
  вживую: контейнер healthy, все параметры подтверждены через SHOW
  VARIABLES.
- Nextcloud + Redis: образ nextcloud:apache, автоустановка через env
  (MYSQL_*, NEXTCLOUD_ADMIN_*, NEXTCLOUD_TRUSTED_DOMAINS, REDIS_HOST).
  Проверено через `occ status` (installed: true, version 34.0.1) и
  `occ config:list system`: memcache.locking/distributed = Redis,
  mysql.utf8mb4 = true, trusted_domains содержит домен.
  depends_on с condition service_healthy на mariadb и redis.
- nginx: TLS termination настоящим prod-сертификатом из ./letsencrypt/,
  HTTP→HTTPS редирект (301), HSTS. Explicit subnet 172.28.0.0/24 для
  nextcloud_net (нужен для TRUSTED_PROXIES). У Nextcloud выставлены
  TRUSTED_PROXIES=172.28.0.0/24, OVERWRITEPROTOCOL=https,
  OVERWRITEHOST/OVERWRITECLIURL=домен. client_max_body_size 0 и
  proxy_request_buffering off — под грядущую загрузку 2GB файла
  (не буферизировать целиком в nginx).
  Проверено вживую с Windows-стороны обычным `curl` (без -k):
  HTTP 200 на /status.php, 301 редирект с http, реальный
  issuer=Let's Encrypt в TLS-хендшейке.
  Грабли: Nextcloud (через свой .htaccess в образе apache) сам уже
  выставляет X-Content-Type-Options/X-Frame-Options/X-Permitted-Cross-
  Domain-Policies/X-Robots-Tag/Referrer-Policy — если те же заголовки
  добавлять ещё и в nginx, они дублируются в ответе. Оставили в nginx
  только Strict-Transport-Security (единственный, который сам апстрим
  надёжно не проставляет).
- Задача 6 (чистый Overview): `occ db:add-missing-indices`,
  `occ db:convert-filecache-bigint -n` (всё уже up to date на свежей
  установке), `default_phone_region=LV`, `maintenance_window_start=1`,
  `occ background:cron`. Добавлен sidecar-контейнер `cron` (тот же
  образ nextcloud:apache, entrypoint `/cron.sh` — busybox crond по
  встроенному в образ crontab `*/5 * * * * php -f cron.php`). Прогнали
  `cron.php` вручную — `lastcron` обновился, ошибок нет.
  Проверили PHP-модули (`bcmath, gmp, imagick, intl, redis, apcu, zip` —
  все на месте) и OPcache (`interned_strings_buffer=32,
  max_accelerated_files=10000, memory_consumption=128` — уже
  соответствует рекомендациям Nextcloud из коробки, кастомный php.ini
  не понадобился: официальный образ уже так собран).
  Нашли и починили: `.well-known/carddav` и `/caldav` редиректили на
  `http://`, а не `https://` (Apache сам не знает, что соединение TLS,
  т.к. между nginx и apache трафик обычный HTTP) — обработали эти два
  location'а прямо в nginx (`return 301 https://...`), как советует
  официальная документация Nextcloud для reverse-proxy.
- Задача 7 (2GB upload): загрузили/скачали через WebDAV
  (`remote.php/dav/files/admin/...`) сгенерированный 2GB файл со
  случайным содержимым. md5 до и после **идентичны**
  (e41d5a5ffcee897cb54c5672c3dac212). Тестовый файл лежит в
  `test-2gb.bin` в корне репо (gitignored, `*.bin`) — готов для
  повторной загрузки вживую на встрече.
  Грабли: получили 413 от **Apache** (не nginx!) на первой попытке —
  `LimitRequestBody` в apache-limits.conf образа читает отдельную
  переменную `APACHE_BODY_LIMIT`, дефолт 1GiB, и наш
  `PHP_UPLOAD_LIMIT=20G` на неё не влияет (это разные лимиты на разных
  уровнях стека). Выставили `APACHE_BODY_LIMIT: 0` в docker-compose.
- Задача 8 (Desktop Client): создали отдельного non-admin пользователя
  `nikita` (не синкать как admin). Логин в клиенте прошёл **без единого
  предупреждения о сертификате** — ключевое требование задания
  подтверждено вживую, не только curl'ом. Синк файлов отработал,
  открылся веб-UI dashboard.
  По пути через веб-UI обнаружили и добили остатки Задачи 6 (Overview):
  - Ошибка в логах — это была наша уже пофикшенная 413-ошибка из
    Задачи 7 (историческая, лог почищен).
  - `occ maintenance:repair --include-expensive` — mimetype-миграции.
  - **HSTS-заголовок "не установлен" по мнению Overview**, хотя curl
    снаружи его видел. Причина: Docker Desktop прокидывает Windows
    hosts-файл во внутренний DNS контейнеров, из-за чего
    NC_DOMAIN резолвился внутри `nc_app` в 127.0.0.1 — loopback самого
    контейнера, где на 443 никто не слушает. Self-check Nextcloud (сам
    себе ходит по HTTPS проверить заголовки) не мог достучаться.
    Решение: статический IP 172.28.0.10 у nginx в docker-compose +
    `extra_hosts` у nextcloud/cron, форсирующий резолвинг домена на
    nginx вместо унаследованного 127.0.0.1.
  Осталось 4 пункта в Overview — намеренно не закрывали, задание это
  прямо разрешает при документировании причины:
  - **AppAPI deploy daemon** — не используем External Apps (ExApps),
    не применимо.
  - **2FA не forced** — доступна, но не обязательна: включение
    потребовало бы кода/backup-кодов на живой демонстрации, это риск,
    не выгода, для одноразового теста.
  - **Email server не настроен** — нет доступного SMTP-релея в
    локальном окружении без интернет-провайдера почты; в проде был бы
    настоящий SMTP компании.
  - **Server ID не настроен** — актуально только для нескольких
    PHP-серверов (горизонтальное масштабирование), у нас один сервер.
Следующий шаг: Задача 9 — воспроизводимость (Makefile, bootstrap.sh).
