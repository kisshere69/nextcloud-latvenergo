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
        ├── nextcloud (php-fpm или apache)
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
| 0 | Подготовка: WSL2, Docker, скелет репо | [ ] |
| 1 | Hostname: DuckDNS + hosts (Windows + WSL) | [ ] |
| 2 | TLS: Let's Encrypt DNS-01 (staging → prod) | [ ] |
| 3 | MariaDB: utf8mb4, InnoDB параметры, healthcheck | [ ] |
| 4 | Nextcloud + Redis | [ ] |
| 5 | nginx: TLS termination, security headers, redirects | [ ] |
| 6 | Чистый Overview: все occ-команды | [ ] |
| 7 | Загрузка 2 GB файла, md5 проверка | [ ] |
| 8 | Desktop Client: синк без предупреждений | [ ] |
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

Текущий статус: читаем задание, создаём скелет проекта.
Следующий шаг: Задача 0 — проверка WSL2 и Docker.
