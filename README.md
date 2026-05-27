# ⚡ power-yt — самостоятельный медиа-стек на Docker

![License](https://img.shields.io/badge/license-MIT-blue)
![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Jellyfin](https://img.shields.io/badge/Jellyfin-NVENC-00A4DC?logo=jellyfin&logoColor=white)
![Storage](https://img.shields.io/badge/storage-TrueNAS%20%2F%20NFS-0095D5)
![SSO](https://img.shields.io/badge/SSO-Keycloak%20%2B%20oauth2--proxy-4D4D4D)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)

Автоматизированная домашняя медиа-инфраструктура: **Jellyfin + *arr + qBittorrent + Seerr**,
хранилище на **TrueNAS (ZFS) по NFS**, аппаратное транскодирование **NVIDIA NVENC**,
внешний доступ через **Traefik (VDS) по WireGuard** и единый вход **SSO (Keycloak + oauth2-proxy)**.

> Один `docker-compose.yml`, инфраструктура как код, секреты вне репозитория, миграция auth-слоя через GitHub Actions.

---

## ✨ Возможности

- 🎬 **Медиасервер** Jellyfin с NVENC (RTX 3070 Ti, h264/hevc).
- 🤖 **Автоматизация** Sonarr / Radarr / Lidarr / Whisparr + Prowlarr (индексаторы) + Bazarr (субтитры).
- ⬇️ **Загрузки** qBittorrent с категориями и atomic-move.
- 🔗 **Hardlinks работают** — `torrents/` и `media/` в одном NFS-датасете (мгновенный импорт, без дублей).
- 🎚️ **Форматы по TRaSH** — Recyclarr заливает quality profiles / custom formats.
- 🧹 **Гигиена** Cleanuparr (чистка зависших) + Unpackerr (распаковка).
- 📊 **Статистика** Jellystat, 🎞️ **транскод** Tdarr (NVENC), 📨 **запросы** Seerr.
- 🔐 **SSO** Keycloak + oauth2-proxy (forward-auth) для admin-приложений.
- 🌐 **Внешний доступ** через Traefik на VDS, трафик — по WireGuard.

## 🧩 Состав стека

| Сервис | Назначение | Порт |
|---|---|---|
| Jellyfin | медиасервер (NVENC) | 8096 |
| Sonarr / Radarr / Lidarr / Whisparr | сериалы / фильмы / музыка / xxx | 8989 / 7878 / 8686 / 6969 |
| Prowlarr | индексаторы | 9696 |
| Bazarr | субтитры | 6767 |
| qBittorrent | загрузки | 8080 |
| Seerr | портал запросов | 5055 |
| Jellystat | статистика Jellyfin | 3000 |
| Tdarr | транскод библиотеки | 8265 |
| Cleanuparr / Unpackerr / Recyclarr / FlareSolverr | обслуживание | — |

## 🏗️ Архитектура

```
TrueNAS (ZFS) ──NFS──► /mnt/storage/data ──(bind)──► /data во всех контейнерах   (hardlinks!)
                              ▲
GPU: NVIDIA NVENC ── Jellyfin / Tdarr (runtime: nvidia)

Интернет ─► media.victory62.org (VDS, белый IP, Traefik, Cloudflare DNS-01)
            └─ WireGuard 10.10.0.0/24 ─► хост 10.10.0.189:<порт>
                 admin-приложения ─► forward-auth ─► oauth2-proxy ─► Keycloak (SSO)
```

- **Хранилище** — ZFS-датасет TrueNAS, отдан по NFS; диски пулит ZFS, бэкап — Cloud Sync на NAS.
- **Доступ** — поддомены (Jellyfin/Seerr/qBit) + пути `media.victory62.org/<app>` (URL Base в *arr).
- **Аутентификация** — `auth/` стек, изолированная среда, миграция на отдельную машину через CI.

## 🚀 Установка

**Требования:** Docker + Compose, NVIDIA Container Toolkit, доступ к NFS-хранилищу, WireGuard.

```bash
git clone https://github.com/nick4man/power-yt.git && cd power-yt
cp .env.example .env                 # PUID/PGID/UMASK/TZ, BIND_IP (WG), пути, теги образов
sudo ./scripts/bootstrap.sh          # config-каталоги + torrents/ структура

# хранилище: NFS-датасет TrueNAS как /data
sudo cp systemd/mnt-storage-data.mount /etc/systemd/system/
sudo cp systemd/docker-after-storage.conf /etc/systemd/system/docker.service.d/10-after-storage.conf
sudo systemctl daemon-reload && sudo systemctl enable --now mnt-storage-data.mount

docker compose pull && docker compose up -d
docker compose ps                    # все healthy
```

Подробно — в [`docs/runbook.md`](docs/runbook.md) (NVENC, hardlink-тест, TRaSH, WireGuard/Traefik).

## 🔧 Использование

- **Доступ**: Jellyfin `:8096`, Seerr `:5055`, *arr по своим портам (см. таблицу). Снаружи — через Traefik на VDS.
- **Настройка по TRaSH**: root-папки `/data/media/{movies,tv,music}`, download client → qBittorrent, индексаторы в Prowlarr → синк в *arr.
- **Форматы**: Recyclarr применяет quality profiles (WEB-1080p / HD Bluray+WEB) + custom formats; в Seerr они заданы как дефолтные.
- **Внешний доступ**: A-записи доменов → IP VDS; конфиг Traefik — [`docs/traefik-media.example.yml`](docs/traefik-media.example.yml).

## 🔐 Аутентификация (SSO)

Каталог [`auth/`](auth/) — **Keycloak + oauth2-proxy** (forward-auth), изолированная среда с разносом по сетям
(`auth_backend` internal + `auth_edge`). Локальный стенд эмулирует прод (профиль `emulation`),
боевой слой (профиль `core`) переносится на отдельную машину. Полный e2e-тест: [`auth/e2e-test.sh`](auth/e2e-test.sh).

## 🤖 CI/CD

[`.github/workflows/auth-ci.yml`](.github/workflows/auth-ci.yml): **validate** (compose config на каждый push/PR) +
**deploy** (по `workflow_dispatch`/main → SSH-миграция `core` на третью машину). Секреты — в GitHub Secrets
(см. [`auth/README.md`](auth/README.md)).

## 🗺️ Roadmap

- [ ] Миграция auth-стека на выделенную машину через CI (готово к запуску).
- [ ] OIDC-логин в самом Jellyfin (плагин SSO + client в Keycloak).
- [ ] Бэкап конфигов (`*/config`) через restic по таймеру.
- [ ] Мониторинг: Prometheus + Grafana (exporters arr/qBit/Jellyfin).
- [ ] Healthchecks для Cleanuparr/Jellystat/Tdarr + автотесты в CI.
- [ ] Опциональный VPN (gluetun) для qBittorrent.
- [ ] Helm/Compose-профили под разные конфигурации хранилища (NFS / mergerfs+rclone / локально).
- [ ] Usenet-ветка (SABnzbd) как альтернатива torrent.

## 🔒 Безопасность

Секреты **не хранятся в репозитории**: `.env`, `rclone/*.conf`, `*/config/`, `auth/.env`, БД и runtime-данные — в `.gitignore`.
Правьте из `*.example`. Admin-приложения закрыты (basic-auth → Keycloak SSO). Порты публикуются только на WG-интерфейс.

## 📁 Структура

```
docker-compose.yml          # медиа-стек
.env.example                # переменные
scripts/ systemd/ rclone/   # хранилище (NFS/TrueNAS) + bootstrap
docs/                       # runbook + Traefik-конфиг VDS
auth/                       # Keycloak+oauth2-proxy (SSO) + локальная эмуляция
.github/workflows/          # CI/CD
```

## 📄 Лицензия

[MIT](LICENSE) — используйте, изменяйте и распространяйте свободно.

---

*Инфраструктура как код. Сделано с помощью Claude Code.*
