# Рабочие заметки

Сюда записываем: каждую ошибку, каждый варнинг и как он решался.
Из этого потом собирается техдокументация и материал для разговора на встрече.

---

## 2026-07-13

- Задание получено от Latvenergo (homework-is-inz-2026.docx)
- Создан план выполнения (latvenergo-nextcloud-plan.md)
- Создан скелет проекта nextcloud-latvenergo/
- Следующий шаг: Задача 0 — проверка WSL2 и Docker

### Задача 0 — WSL2 + Docker

- WSL 2.7.10, ядро 6.18, Ubuntu 20.04.6 LTS. Docker Desktop 4.80.0
  (Engine 29.6.1, Compose v5.3.0).
- **Проблема:** команда `docker` не найдена внутри `Ubuntu-20.04`, хотя
  Docker Desktop запущен. Причина: в Docker Desktop интеграция с WSL
  включается либо для "default"-дистрибутива (у нас им был
  `docker-desktop`, служебный), либо вручную по чекбоксу на конкретный
  дистрибутив. **Решение:** Docker Desktop → Settings → Resources →
  WSL Integration → включить тумблер для `Ubuntu-20.04`.
- Диск 955G свободно, память 13G свободно — с запасом под 2GB тестовый
  файл и весь стек.

### GitHub-репозиторий

- Fine-grained personal access token сначала не мог **создать**
  репозиторий (`Resource not accessible by personal access token`) —
  у токена не было Account permission "Administration". Создали репо
  вручную через github.com/new.
- После создания репо токен всё ещё не мог **писать** в него (403 и на
  `git push`, и на Contents API), хотя "Read" работал. Причина: в
  Repository permissions токена был выдан только "Administration"
  (управление настройками репо) — это НЕ даёт доступа к содержимому.
  **Решение:** добавить отдельное право **Contents: Read and write**.
- Тестовые коммиты, сделанные через Contents API во время проверки прав
  (создание/удаление тестового файла), разошлись с локальной историей
  → `git push` отклонён (`fetch first`). Слили через
  `git merge --allow-unrelated-histories` (net-diff был нулевой, конфликтов
  не было).

### Задача 1 — DuckDNS + hosts

- Windows hosts (`C:\Windows\System32\drivers\etc\hosts`) требует прав
  администратора на запись. Попытка через `Start-Process -Verb RunAs`
  из автоматизации не сработала предсказуемо (UAC подтверждали, но
  правка не применялась) — в итоге правили вручную через Notepad,
  запущенный "от имени администратора".
- В WSL правка `/etc/hosts` **не сохраняется** между перезапусками — файл
  автогенерируется при каждом старте дистрибутива. Нужно сначала
  прописать в `/etc/wsl.conf` `[network] generateHosts = false`.
- **Грабли:** команда добавления секции `[network]` в `wsl.conf` была
  случайно выполнена дважды → задвоенный ключ и warning
  `Duplicated config key 'network.generateHosts'`. Почищено
  перезаписью файла целиком.
- **Грабли:** `sudo` внутри `wsl -d Ubuntu-20.04 -- bash -lc "sudo ..."`
  зависает навсегда в ожидании пароля — нет интерактивного TTY для
  ввода. **Решение для скриптовых/неинтерактивных команд:**
  `wsl -d Ubuntu-20.04 -u root -- ...` вместо `sudo` — исполняет команду
  сразу от root, без запроса пароля.
- **Грабли (повторяющиеся):** после `wsl --terminate Ubuntu-20.04`
  (нужен был для применения `wsl.conf`) интеграция Docker Desktop с этим
  дистрибутивом слетала повторно — тумблер в Docker Desktop приходилось
  включать заново несколько раз за сессию. Похоже на race condition:
  Docker Desktop не всегда успевает переинжектить `/mnt/wsl/docker-desktop`
  сразу после холодного старта дистрибутива.

### Задача 2 — TLS (Let's Encrypt DNS-01 через DuckDNS)

- DuckDNS поддерживает ACME DNS-01 "из коробки": TXT-значение,
  отправленное через их обычный update API
  (`?domains=<sub>&token=<token>&txt=<value>`), автоматически публикуется
  по адресу `_acme-challenge.<sub>.duckdns.org>`, который и проверяет
  Let's Encrypt. Отдельного DNS-плагина не понадобилось — два простых
  shell-хука (`--manual-auth-hook` / `--manual-cleanup-hook`) с `curl`.
- **Проблема:** `docker pull certbot/certbot` внутри WSL падал с
  `error getting credentials - err: fork/exec
  /usr/bin/docker-credential-desktop.exe: exec format error`.
  Причина: `~/.docker/config.json` в WSL был настроен на
  `"credsStore": "desktop.exe"` (Windows-бинарник), а WSL interop для
  исполнения `.exe`-файлов из Linux в этот момент не срабатывал.
  Для анонимного pull публичного образа credential store вообще не
  нужен — **решение:** очистить `~/.docker/config.json` до `{}`.
- Сначала прогнали `certbot/renew.sh staging` (тестовый CA Let's Encrypt,
  не тратит rate-limit прод-CA) — весь DNS-01 флоу отработал с первого
  раза. После этого прогнали `prod` — получили настоящий сертификат
  (`issuer=Let's Encrypt`, не staging), действителен до 2026-10-11.
- Следующий шаг: Задача 3 — MariaDB (utf8mb4, InnoDB, healthcheck).

### Задача 3 — MariaDB

- Взяли `mariadb:10.11` (LTS, официально рекомендован Nextcloud).
  Актуальные для этой версии параметры задаются через `command:` в
  docker-compose (не через кастомный my.cnf — проще для воспроизводимости):
  `transaction-isolation=READ-COMMITTED`, `binlog-format=ROW`,
  `innodb-file-per-table=1`, `character-set-server=utf8mb4`,
  `collation-server=utf8mb4_general_ci`, `max-allowed-packet=128M`,
  `innodb-buffer-pool-size=1G`.
- Устаревшие рекомендации из старых гайдов по Nextcloud/MariaDB
  (`innodb_large_prefix`, `innodb_file_format=barracuda`) для 10.11 не
  нужны — это поведение по умолчанию с MariaDB 10.3+, явно выставлять
  их сейчас не даст ошибку, но это просто мёртвые настройки.
- Healthcheck — не свой скрипт, а встроенный в официальный образ
  `healthcheck.sh --connect --innodb_initialized`: он же проверяет и то,
  что сервер принимает соединения, и то, что InnoDB полностью
  инициализирован (важно, чтобы Nextcloud не пытался подключиться в
  момент, когда MariaDB ещё поднимается).
- Проверено вживую: `docker compose up -d mariadb` → healthy за ~10
  секунд, `SHOW VARIABLES` подтвердил все нужные значения
  (utf8mb4 / utf8mb4_general_ci / READ-COMMITTED / ROW / ON / 128M / 1G).

### Задача 4 — Nextcloud + Redis

- Выбрали образ `nextcloud:apache`, а не `nextcloud:fpm`. Причина:
  с apache-образом nginx (Задача 5) делает простой `proxy_pass` на
  порт 80 контейнера; с fpm пришлось бы городить `fastcgi_pass` и
  `fastcgi_param` в nginx и делить volume с PHP-файлами между
  контейнерами — больше движущихся частей без выигрыша для этого
  масштаба задачи.
- Официальный образ Nextcloud сам разруливает автоустановку через
  переменные окружения (`MYSQL_HOST/DATABASE/USER/PASSWORD`,
  `NEXTCLOUD_ADMIN_USER/PASSWORD`, `NEXTCLOUD_TRUSTED_DOMAINS`,
  `REDIS_HOST`) — не пришлось руками прогонять `occ maintenance:install`.
- `depends_on` с `condition: service_healthy` на mariadb и redis — без
  этого Nextcloud иногда стартует раньше, чем БД готова принимать
  соединения, и автоустановка падает.
- Проверено вживую после `docker compose up -d`:
  - `docker exec nc_app php occ status` → `installed: true`,
    `version: 34.0.1.2`.
  - `docker exec nc_app php occ config:list system` → подтвердил, что
    `memcache.locking` и `memcache.distributed` уже указывают на Redis
    (это заранее закрывает варнинг "memcache/file locking" в Overview,
    см. таблицу выше), `mysql.utf8mb4: true`, `trusted_domains`
    содержит `nextcloud-nikita.duckdns.org`.
- Сознательно НЕ выставляли пока `OVERWRITEPROTOCOL=https` /
  `OVERWRITECLIURL` — это будет иметь смысл только вместе с nginx
  (Задача 5); если включить раньше, любые прямые http-проверки
  контейнера превратятся в редирект-петли.

### Задача 5 — nginx (TLS termination, security headers, редиректы)

- `docker-compose.yml`: сети нужен явный `ipam.config.subnet`
  (172.28.0.0/24), иначе Docker Compose назначает subnet автоматически
  и он может смениться между пересозданиями — а `TRUSTED_PROXIES` у
  Nextcloud завязан именно на IP/CIDR, не на имя хоста.
- После смены subnet сети `docker compose up -d` не пересоздаёт сеть
  сам по себе — потребовался `docker compose down && docker compose up -d`.
- Для реальной 2GB-загрузки в nginx выставили `client_max_body_size 0`
  (без лимита) и, что важнее, `proxy_request_buffering off` — без этого
  nginx буферизирует всё тело запроса на диск/в память перед тем как
  переслать на бэкенд, что для больших файлов и chunked-загрузок
  Nextcloud Desktop Client может привести к таймаутам и лишней нагрузке
  на диск.
- **Грабли:** после первого прогона с добавленными в nginx security-
  заголовками (`X-Content-Type-Options`, `X-Frame-Options`,
  `X-Permitted-Cross-Domain-Policies`, `X-Robots-Tag`,
  `Referrer-Policy`) в `curl -I` эти же заголовки оказались
  **задублированы** в ответе. Причина: образ `nextcloud:apache`
  добавляет их сам через собственный `.htaccess`. `Strict-Transport-
  Security` не задублировался — apache его не выставляет (не может
  быть уверен, что соединение действительно TLS). Решение: убрали из
  nginx всё, кроме HSTS — остальное и так приходит от бэкенда.
- Проверено вживую с Windows-стороны обычным `curl` (без флага `-k`,
  как и требует задание):
  - `http://` → 301 на `https://`.
  - `https://.../status.php` → 200, тело корректное, TLS-хендшейк
    (`openssl s_client`) показывает `issuer=Let's Encrypt`.
  - `curl -I` подтвердил единственный набор security-заголовков без
    дублей после правки.

### Задача 6 — чистый Overview

- Прогнали стандартный набор `occ`-команд: `db:add-missing-indices`
  (на свежей установке нечего добавлять), `db:convert-filecache-bigint
  -n` ("All tables already up to date!" — тоже ожидаемо для новой
  установки, актуально в основном при апгрейде со старых версий),
  `config:system:set default_phone_region --value=LV`,
  `config:system:set maintenance_window_start --value=1 --type=integer`,
  `background:cron`.
- Переключить режим на cron мало — сам cron.php кто-то должен дёргать
  каждые 5 минут. В докер-окружении для этого нет системного cron по
  умолчанию. Официальный образ `nextcloud:apache` уже содержит готовый
  `/cron.sh` (запускает `busybox crond`) и сам прописывает
  `*/5 * * * * php -f /var/www/html/cron.php` в crontab для www-data
  при старте контейнера — решение было не писать что-то своё, а
  поднять **второй сервис на том же образе** с `entrypoint: /cron.sh`,
  делящий volume `nc_data` с основным приложением. Стандартный паттерн
  из официальной документации образа.
- Проверили не "на веру", а по факту: руками прогнали
  `php -f cron.php` внутри `nc_cron` и сверили `occ config:app:get
  core lastcron` с текущим unix-time — совпало с точностью до пары
  секунд.
- Проверили PHP-модули (`php -m`) и OPcache (`php -i`) — оказалось, что
  официальный образ уже содержит все модули, которые Nextcloud просит
  в Overview (bcmath, gmp, imagick, intl, apcu, redis, zip), и OPcache
  уже настроен по рекомендациям (interned_strings_buffer=32,
  max_accelerated_files=10000, memory_consumption=128,
  save_comments=On). Кастомный php.ini не понадобился — логично, т.к.
  это официальный образ, специально собранный под Nextcloud.
- **Грабли:** `curl` на `/.well-known/carddav` и `/.well-known/caldav`
  показал редирект на `http://...`, а не `https://...`, хотя весь
  трафик снаружи идёт по HTTPS. Причина: эти два редиректа генерирует
  сам Apache через mod_rewrite в `.htaccess`, а Apache видит только
  внутренний HTTP-хоп от nginx и не в курсе, что снаружи TLS (в отличие
  от Nextcloud PHP-уровня, который правильно читает `X-Forwarded-Proto`
  благодаря `TRUSTED_PROXIES`/`OVERWRITEPROTOCOL`). Решение — не чинить
  Apache, а перехватить оба location'а на уровне nginx и отдавать
  редирект самим (`return 301 https://$host/remote.php/dav`) — это и
  есть рекомендация из официальных nginx-примеров для Nextcloud
  за reverse-proxy.

### Задача 7 — загрузка 2GB файла, проверка md5sum

- Генерировали тестовый файл (`dd if=/dev/urandom bs=4M count=512`)
  внутри нативной WSL-файловой системы (`/tmp`), а не на примонтированном
  Windows-диске (`/mnt/c/...`) — там I/O через 9p/drvfs заметно
  медленнее для операций такого объёма. 2GB случайных данных сгенерировалось
  за ~5 секунд (450 МБ/с).
- Загружали и скачивали не через браузер, а напрямую по WebDAV
  (`PUT`/`GET` на `remote.php/dav/files/admin/...`) — это тот же
  протокол, которым пользуется Desktop Client, и его проще
  автоматизировать и проверить из командной строки. Реальный клиент
  живьём — отдельно, Задача 8.
- **Грабли:** первая попытка загрузки 2GB файла упала с
  `413 Request Entity Too Large` — причём страница ошибки была именно
  от **Apache**, не от nginx (у nginx `client_max_body_size 0` уже был
  выставлен в Задаче 5). Оказалось, что образ `nextcloud:apache`
  использует отдельную переменную окружения `APACHE_BODY_LIMIT`
  (директива `LimitRequestBody` в `apache-limits.conf`), у которой свой
  дефолт — 1 GiB (1073741824), никак не связанный с
  `PHP_UPLOAD_LIMIT`. То есть в этом стеке лимит на размер запроса
  проверяется в трёх независимых местах: nginx (`client_max_body_size`),
  Apache (`LimitRequestBody`/`APACHE_BODY_LIMIT`) и PHP
  (`upload_max_filesize`/`post_max_size`/`PHP_UPLOAD_LIMIT`) — не хватит
  поправить только один. Решение: `APACHE_BODY_LIMIT: 0` (без лимита,
  как и у nginx) в `docker-compose.yml`.
- После правки: загрузка 2GB — ~11 секунд, скачивание обратно — ~9
  секунд (localhost, без реальной сети). `md5sum` файла до загрузки и
  после скачивания **совпал побитно**
  (`e41d5a5ffcee897cb54c5672c3dac212`). WebDAV `PROPFIND` также
  подтвердил точный размер (`2147483648` байт) на стороне сервера.
- Тестовый файл удалили с сервера после проверки (чтобы инстанс был
  чистым для живой демонстрации), но сохранили локально —
  `test-2gb.bin` в корне репозитория (подпадает под `*.bin` в
  `.gitignore`, в git не попадёт).

### Задача 8 — Nextcloud Desktop Client

- В клиенте три пункта на старте: "Log in" (Войти), "Sign up with a
  provider" и "Host your own server". Последний — это НЕ поле для
  ввода своего сервера, а ссылка на документацию по установке (для
  тех, у кого сервера ещё нет). Нужный пункт — "Log in".
- Для синка сознательно завели отдельного **не-admin** пользователя
  (`occ user:add`) — admin не должен использоваться для повседневной
  синхронизации файлов.
- Результат: логин прошёл **без единого предупреждения о
  сертификате** — это и есть прямая, "живая" проверка требования
  задания (не через curl, а через реальный клиент). Синк файлов
  отработал корректно.
- Пока разбирались с Overview через веб-UI, поймали важный нюанс:
  обычный пользователь (`nikita`) не видит пункт "Administration" в
  Settings — это не баг, а ожидаемое поведение (только у admin есть
  доступ к серверным настройкам).

### Довески к Задаче 6 — найдено при разборе Overview через браузер

- Ошибка в логах (1 шт.) — это была наша уже пофикшенная 413-ошибка из
  Задачи 7. Почистили лог (`truncate -s 0 nextcloud.log`), чтобы
  Overview не путал историю с текущим состоянием.
- `occ maintenance:repair --include-expensive` — закрыл предупреждение
  про mimetype-миграции (команда ровно та, что подсказывает сам
  Overview).
- **Самый интересный баг сессии:** Overview показывал "Strict-
  Transport-Security header is not set", хотя `curl -I` снаружи чётко
  показывал этот заголовок. Разобрались: Nextcloud проверяет
  собственные security-заголовки, делая HTTP-запрос **сам к себе** по
  публичному домену. Docker Desktop прокидывает Windows hosts-файл во
  внутренний DNS контейнеров (embedded resolver 127.0.0.11 →
  192.168.65.7 → хостовый резолвер) — из-за этого домен резолвился
  внутри контейнера `nc_app` в `127.0.0.1`, а это loopback **самого**
  `nc_app`, где слушает только Apache на 80, TLS там нет вообще.
  Self-check не мог достучаться и решал, что заголовка нет.
  Решение — не бороться с Docker DNS, а прибить домен явно:
  статический IP `172.28.0.10` у nginx (`ipv4_address` в
  docker-compose) + `extra_hosts` у `nextcloud`/`cron`, указывающий
  этот домен прямо на nginx. Проверили эмуляцией самого self-check'а —
  `docker exec nc_app curl -I https://<домен>/` — заголовок появился.
- Осталось 4 сознательно не закрытых предупреждения (см. обоснование
  в CONTEXT.md): AppAPI deploy daemon, 2FA не forced, email server не
  настроен, server ID не настроен. Все четыре не относятся к задаче
  ("не используем ExApps", "форсинг 2FA сломает демо", "нет SMTP в
  локальном окружении", "один PHP-сервер, ID не нужен").

### Задача 9 — воспроизводимость (Makefile, bootstrap.sh)

- Курица-яйцо: `make` в свежей Ubuntu-20.04 (WSL) не установлен по
  умолчанию — а без `make` не запустить ни один Makefile-таргет,
  включая гипотетический `make bootstrap`. Это единственная ручная
  зависимость, которую нельзя закрыть самим Makefile:
  `apt-get install -y make` один раз, дальше всё через `make`.
- `scripts/bootstrap.sh` сознательно не пытается автоматически
  чинить Windows hosts-файл (уже знаем с Задачи 1 — туда без прав
  администратора не залезть надёжно из автоматизации) — вместо этого
  падает с понятной инструкцией, что и куда дописать руками.
- В `scripts/post-install.sh` добавили идемпотентное создание
  desktop-пользователя (`DESKTOP_USER`/`DESKTOP_USER_PASSWORD` из
  `.env`) — без этого `make nuke` откатывал бы среду в состояние без
  `nikita`, и пришлось бы каждый раз руками пересоздавать юзера для
  Desktop Client. Проверка на существование через
  `occ user:list | grep`, чтобы повторный запуск не падал на
  "user already exists".
- Грабли: healthcheck у `nc_app` (`exec 3<>/dev/tcp/localhost/80`)
  всегда показывал `unhealthy`, хотя сайт реально отвечал 200. Причина:
  Docker's `CMD-SHELL` в healthcheck выполняется через `/bin/sh`
  внутри контейнера, а `/bin/sh` в образе nextcloud:apache — это
  dash, не bash; `/dev/tcp/...` — это bashism, dash с ним не работает
  ("cannot create /dev/tcp/localhost/80: Directory nonexistent").
  Заменили на `curl -f http://localhost/status.php` (в образе есть
  и `bash`, и `curl` — проверили `docker exec ... which bash curl`).
- Прогнали по-настоящему (не только написали скрипты и понадеялись):
  `make nuke && make up && make post-install` — полный снос данных
  (`docker compose down -v`, сертификат не трогает, он в bind-mount
  `./letsencrypt`, не в volume) и подъём с нуля. Уложилось в ~40 секунд
  (образы уже локально закешированы — на действительно чистой машине
  добавится время на `docker pull`). После цикла: `occ status`
  показывает свежую установку, `admin` и `nikita` пересозданы с теми
  же паролями из `.env`, все healthcheck зелёные, HTTPS отвечает 200.

### Задача 10 — мониторинг (Prometheus/Grafana/Loki) + auto-renewal

- Минимальный набор метрик по договорённости: node-exporter (хост),
  cAdvisor (контейнеры), mysqld-exporter (MariaDB), nginx-exporter
  (через `stub_status`, отдельный внутренний сервер на :8080 в nginx,
  наружу не публикуется). Все 5 таргетов подтверждены как `up` через
  `/api/v1/targets` Prometheus.
- Grafana: datasources и 2 дашборда (Host Overview, Containers)
  провижинятся файлами через docker-compose volumes — после `make up`
  сразу есть что показать, без ручного клика "Add data source".
- Loki/Promtail: используем `docker_sd_configs` (discovery контейнеров
  через `docker.sock`), а не голое монтирование лог-файлов — так
  автоматически подтягиваются новые контейнеры без правки конфига.
  Проверили не "конфиг применился", а по факту: живой запрос через
  Loki API вернул реальные строки access-лога `nc_app` (heartbeat/
  notifications от уже открытого браузера).
- **Грабли:** `mysqld-exporter:latest` (0.19.0) больше не принимает
  `DATA_SOURCE_NAME` из env (в логах: `no user specified in section or
  parent`, `.my.cnf` не найден) — в этой версии креды читаются только
  из `.my.cnf`-файла (осознанное решение апстрима не светить пароль в
  `docker inspect`/списке процессов). Не стали класть файл с паролем в
  репозиторий — вместо этого `entrypoint` контейнера генерирует
  `/tmp/.my.cnf` из переменной `.env` при каждом старте и запускает
  `mysqld_exporter --config.my-cnf=/tmp/.my.cnf`.
- **Грабли (не до конца решаемые в этом окружении):** cAdvisor не
  отдаёт метрики по отдельным контейнерам — только по системным
  cgroup-срезам верхнего уровня (`/docker`, `/system.slice/...`).
  В логах: `failed to identify the read-write layer ID for container
  ...`. Причина — Docker Desktop использует containerd snapshotter
  (мы это видели ещё в Задаче 0, `UseContainerdSnapshotter: true` в
  настройках), а классическая логика cAdvisor резолвит контейнер в его
  read-write layer только для overlay2 graphdriver. Попробовали:
  (1) более новую версию cAdvisor (v0.47.2 → v0.52.1, где заявлена
  поддержка containerd) и (2) домонтировать `/run/containerd` —
  не помогло, ошибка та же. Дальше не копали (пришлось бы выключать
  containerd snapshotter глобально в Docker Desktop и перезапускать
  его — сочли не стоящим ради одной панели дашборда). Решение:
  дашборд "Containers" показывает агрегированную CPU/memory по всем
  Docker-контейнерам разом (`id="/docker"` — это работает), плюс
  text-панель с пояснением прямо в дашборде. На обычном Linux-хосте
  без Docker Desktop это ограничение не проявляется.
- Auto-renewal: отдельный контейнер `certbot-renew` (тот же образ, что
  и в Задаче 2) крутит `certbot renew` раз в сутки. `certbot renew`
  сам по себе идемпотентен — не трогает сертификат, если тот не близок
  к истечению, поэтому суточный интервал безопасен. `--deploy-hook`
  перезагружает nginx (`docker exec nc_nginx nginx -s reload`) —
  но только при реальном обновлении сертификата, не на каждый холостой
  прогон.
- Прогнали вживую (не только логика на бумаге): `certbot renew` внутри
  `nc_certbot_renew` корректно определил "Certificate not yet due for
  renewal" (истекает 2026-10-11) и ничего не тронул. Отдельно
  проверили сам механизм деплой-хука — `docker exec nc_certbot_renew
  docker exec nc_nginx nginx -t` действительно способен достучаться до
  соседнего контейнера через смонтированный `docker.sock`.
- Осознанный компромисс: `certbot-renew` получает доступ к
  `/var/run/docker.sock` хоста — это даёт контейнеру фактически полный
  контроль над Docker-демоном (может запустить/остановить/подсмотреть
  любой контейнер), что в проде было бы неприемлемо без ограничения
  через docker-socket-proxy. Для одноразового домашнего стенда — осознанно
  принятый риск, но это прямой кандидат в раздел "чего не хватает для
  продакшена".
