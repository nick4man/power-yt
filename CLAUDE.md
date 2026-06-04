# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Медиа-стек на Docker: **Jellyfin + Sonarr + Radarr + Prowlarr + Bazarr + qBittorrent + Jellyseerr**.
Единый `docker-compose.yml` в корне, конфиги сервисов — в `./<service>/config`. Документация по проектированию — TRaSH-Guides.
Полная инструкция установки/эксплуатации и траблшутинг: @docs/runbook.md

## Архитектура хранилища (КРИТИЧНО)

```
TrueNAS SCALE (<NAS_IP>)                          этот хост
  ZFS pool → dataset /mnt/media/data  ──NFSv4──►  /mnt/storage/data ──(bind)──► /data во всех контейнерах
       └─ Cloud Sync Task (rclone) → gdrive/onedrive (бэкап, настраивается в GUI NAS)
```

- `/data` — это **один NFS-датасет** (`<NAS_IP>:/mnt/media/data`), смонтированный systemd-юнитом `systemd/mnt-storage-data.mount`. Внутри — `torrents/` и `media/` в одной ФС.
- **Hardlinks и atomic-move работают нативно** (ZFS — обычная POSIX-ФС, проверено: `nlink=2`). НЕ разносить `torrents/` и `media/` по разным маунтам.
- **Объединение дисков и облако — на стороне TrueNAS**: диски пулит ZFS, бэкап в облако делает встроенный Cloud Sync. На хосте НЕТ mergerfs/rclone-mount/uploader — это сознательно убрано (см. git-историю).
- Всё на NAS принадлежит пользователю `q (uid 1000)`; права на датасете — через **NFSv4 ACL** (POSIX-биты/setgid синтетические, не показатель). Поэтому ключ доступа — `PUID=1000`.

## Команды

```bash
sudo ./scripts/bootstrap.sh                              # config-каталоги + torrents/ на /data (после маунта)
sudo cp systemd/mnt-storage-data.mount /etc/systemd/system/   # NFS-маунт /data
sudo cp systemd/docker-after-storage.conf /etc/systemd/system/docker.service.d/10-after-storage.conf
sudo systemctl daemon-reload && sudo systemctl enable --now mnt-storage-data.mount
docker compose pull && docker compose up -d              # стек
docker compose ps                                        # healthy после start_period
```

## Готчи

- **SELinux включён (Enforcing)**: на `/data` (NFS) метки `:z` НЕ применять — NFS их не хранит. Доступ контейнеров к NFS уже разрешён булином **`virt_use_nfs=on`** (Nextcloud на этом хосте так и работает). Приватные `config` (локальный btrfs) — с `:Z`.
- **NFS-маунт `/data`**: юнит `WantedBy` (НЕ `Requires`) → если NAS недоступен, загрузка/Docker не блокируются. docker drop-in — только `After=` (без `Requires=`), чтобы падение media-NFS не утянуло Docker и соседний Nextcloud.
- **GPU**: NVIDIA через `runtime: nvidia` (НЕ `/dev/dri`-проброс). RTX 3070 Ti = **Ampere → AV1-encode не поддерживается**, в `encoding.xml` стоит `AllowAv1Encoding=false`. h264/hevc NVENC — ок.
- **Единые `PUID=1000`/`PGID=3001`/`UMASK=002`** во всех сервисах (`.env`). Ключевое — `PUID=1000` (владелец данных на NAS); gid вторичен (правит ACL).
- **Секреты**: `.env` и `rclone/rclone.conf` в `.gitignore` (rclone-remote на хосте оставлены для справки/ручных операций; первичный бэкап — Cloud Sync на NAS).
- **Внешний доступ**: порты публикуются на `BIND_IP` (WireGuard-интерфейс), реверс-прокси — Traefik на удалённом VDS. Не биндить на `0.0.0.0`.
- **Отказоустойчивость**: на хосте уже работает контейнер `autoheal` — рестартит сервисы с меткой `autoheal=true` при статусе unhealthy.
- **Соседи на хосте**: Nextcloud-стек (postgres/redis/collabora) + nginx-proxy-manager. Не конфликтовать по портам, помнить про общий Docker.
