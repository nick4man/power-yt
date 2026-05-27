# media-stack — Runbook

Стек: Jellyfin + Sonarr + Radarr + Prowlarr + Bazarr + qBittorrent + Jellyseerr.
Хранилище — **ZFS-датасет на TrueNAS SCALE, отдан по NFS** и смонтирован как единый `/data`.
GPU — NVIDIA NVENC (RTX 3070 Ti). Внешний доступ — Traefik на VDS через WireGuard.

```
TrueNAS SCALE (192.168.0.12)                              этот хост
  ZFS pool → dataset /mnt/media/data ──NFSv4──► /mnt/storage/data ──(bind)──► /data (все контейнеры)
       └─ Cloud Sync Task (rclone) → gdrive/onedrive  (бэкап по расписанию, GUI NAS)
```

Почему так: ZFS уже объединяет диски в один датасет с нативными hardlinks (mergerfs не нужен), а облачный бэкап делает встроенный Cloud Sync TrueNAS. На хосте — только Docker.

---

## 1. Подготовка хоста (root)

```bash
sudo dnf install -y nfs-utils            # NFS-клиент (rclone/fuse для стека не нужны)
sudo ./scripts/bootstrap.sh              # config-каталоги сервисов + точка /mnt/storage/data
```

`virt_use_nfs` SELinux-булин на этом хосте уже `on` (контейнеры могут читать/писать NFS — так же работает Nextcloud). Проверить: `getsebool virt_use_nfs`.

## 2. NFS-экспорт на TrueNAS (один раз, в GUI NAS)

- В TrueNAS: **Datasets** → выбрать датасет медиатеки (`media/data`); владелец/ACL должны давать доступ пользователю с **uid 1000** (наш `PUID`).
- **Shares → Unix (NFS)**: экспортировать датасет на подсеть хоста (`192.168.0.0/24`). Maproot/нужные ACL — чтобы uid 1000 писал.
- Проверить с хоста: `showmount -e 192.168.0.12`.

## 3. Монтирование /data (systemd, root)

```bash
sudo cp systemd/mnt-storage-data.mount /etc/systemd/system/
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cp systemd/docker-after-storage.conf /etc/systemd/system/docker.service.d/10-after-storage.conf
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-storage-data.mount

# Проверка: смонтировано, структура на месте
mountpoint /mnt/storage/data
ls /mnt/storage/data                 # media/ (есть на NAS) + torrents/ (создаст bootstrap)
sudo ./scripts/bootstrap.sh          # повторно — создаст torrents/{movies,tv,music,books}
```

> `.mount`-юнит — `WantedBy` (не `Requires`), а docker drop-in — только `After=`: если NAS недоступен,
> загрузка и Docker не блокируются (Nextcloud в безопасности). Цена — стек поднимется с пустым `/data`.

## 4. Запуск стека

```bash
cp -n .env.example .env        # BIND_IP = адрес WG-интерфейса; PUID=1000/PGID=3000; теги образов
docker compose pull
docker compose up -d
docker compose ps              # все — healthy (первый healthcheck через start_period)
```

## 5. Настройка приложений (по TRaSH-Guides)

- **qBittorrent** (`:8080`, пароль — из `docker logs qbittorrent`): сохранять по категориям в `/data/torrents/{movies,tv,music}`.
- **Prowlarr** (`:9696`): индексаторы → Settings/Apps → подключить Sonarr и Radarr (Sync).
- **Sonarr** (`:8989`) / **Radarr** (`:7878`): Root folder `/data/media/tv` и `/data/media/movies`; download client — qBittorrent (host `qbittorrent`, port `8080`); Quality Profiles / Custom Formats из TRaSH.
- **Bazarr** (`:6767`): подключить Sonarr/Radarr, языки субтитров.
- **Jellyfin** (`:8096`): библиотеки → `/data/media/...` (есть готовые `films`, `xxx` + новые `movies`/`tv`); проверить NVENC.
- **Jellyseerr** (`:5055`): подключить Jellyfin + Sonarr + Radarr.

> Hardlink/atomic-move работают, потому что `torrents/` и `media/` — в одном NFS-датасете. Не задавайте отдельные тома.

## 6. Облачный бэкап — Cloud Sync на TrueNAS (вместо host-uploader)

В GUI TrueNAS SCALE:
- **Credentials → Backup Credentials → Cloud Credentials**: добавить Google Drive / OneDrive (OAuth в браузере; свои client_id/secret — для лимитов API).
- **Data Protection → Cloud Sync Tasks → Add**:
  - Direction **PUSH**, Source = датасет `media/data` (или `.../media`), Target = облачный remote/папка.
  - Transfer mode **COPY** (бэкап) или **SYNC** (зеркало); расписание (напр. ночью); включить snapshot при желании.
- Это полностью заменяет прежний host-side `rclone move`/таймер. Хостовый `rclone/rclone.conf` (remotes `gd/od/smb/nxt`) оставлен для ручных операций, в работе стека не участвует.

## 7. Внешний доступ (WireGuard + Traefik на VDS)

- WG-peer хост↔VDS; адрес WG-интерфейса → `.env` `BIND_IP`.
- Порты публикуются только на `BIND_IP`. На VDS Traefik → `http://<WG_IP>:<порт>`: публично Jellyfin (`8096`), Jellyseerr (`5055`); admin-only — Sonarr/Radarr/Prowlarr/Bazarr/qBittorrent. qBittorrent BT-порт `6881/tcp+udp` — проброс на роутере.

## 8. Бэкап и обслуживание

- Конфиги стека: `*/config` — restic/rsync по таймеру (медиа бэкапит Cloud Sync на NAS).
- Обновления: `docker compose pull && docker compose up -d` (теги лучше пиннить).
- `autoheal` (уже на хосте) рестартит контейнеры со статусом unhealthy.

---

## Проверки (smoke-tests)

```bash
# GPU виден внутри Jellyfin
docker exec jellyfin nvidia-smi                       # RTX 3070 Ti
#  → запустить транскод в Jellyfin, в nvidia-smi появится процесс ffmpeg (NVENC)

# Hardlink: импорт arr НЕ копирует, а линкует (один inode, Links: 2)
stat -c '%i %h %n' /mnt/storage/data/torrents/movies/<file>  /mnt/storage/data/media/movies/<...>/<file>

# NFS примонтирован и переживает рестарт юнита
sudo systemctl restart mnt-storage-data.mount && ls /mnt/storage/data

# Здоровье и доступность
docker compose ps                                     # healthy
curl -fsS http://${BIND_IP:-127.0.0.1}:8096/health    # Jellyfin
```

## Траблшутинг

- **`/data` пуст в контейнере** → NFS не смонтирован или Docker стартовал раньше. `systemctl status mnt-storage-data.mount`, проверь сеть до `192.168.0.12` и экспорт (`showmount -e`).
- **Permission denied на `/data`** → (1) `getsebool virt_use_nfs` должен быть `on`; (2) на NAS датасет/ACL должны давать доступ uid 1000; (3) убедись, что на `/data` в compose НЕТ `:z`.
- **arr копирует вместо hardlink** → `torrents` и `media` должны быть в одном датасете (`/data/...`), а сервисы — под одним `PUID/PGID`. Проверь `stat` (один inode).
- **NVENC не работает** → `docker exec jellyfin nvidia-smi` пуст: проверь `runtime: nvidia` и `nvidia-ctk runtime configure`.
- **NAS недоступен** → стек поднимется с пустым `/data` (так задумано, чтобы не блокировать Docker). После восстановления NAS: `sudo systemctl restart mnt-storage-data.mount && docker compose restart`.
