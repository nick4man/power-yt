#!/usr/bin/env bash
# Готовит хост под media-stack (хранилище = NFS-датасет TrueNAS как /data).
# Создаёт config-каталоги сервисов, точку монтирования и — если NFS уже
# смонтирован — структуру torrents/ рядом с существующей media/.
# Сеть arr-net создаёт сам docker compose.
# Запуск:  sudo ./scripts/bootstrap.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

PUID=1000; PGID=3000; UMASK=002
DATA_ROOT=/mnt/storage/data
[ -f .env ] && set -a && . ./.env && set +a

echo "==> PUID=$PUID PGID=$PGID  DATA_ROOT=$DATA_ROOT"

# 1) Точка монтирования NFS
mkdir -p "$DATA_ROOT"

# 2) Config-каталоги сервисов в репозитории
for svc in jellyfin/config jellyfin/cache jellyfin/transcode \
           sonarr/config radarr/config prowlarr/config bazarr/config \
           qbittorrent/config jellyseerr/config; do
  mkdir -p "$REPO_DIR/$svc"
done
chown -R "$PUID:$PGID" "$REPO_DIR"/{sonarr,radarr,prowlarr,bazarr,qbittorrent,jellyseerr}/config 2>/dev/null || true

# 3) Если датасет уже примонтирован — создать TRaSH-структуру torrents/ (media/ уже есть на NAS)
if mountpoint -q "$DATA_ROOT"; then
  for cat in movies tv music books; do
    install -d -o "$PUID" -g "$PGID" -m 2775 "$DATA_ROOT/torrents/$cat"
    install -d -o "$PUID" -g "$PGID" -m 2775 "$DATA_ROOT/media/$cat"   # idempotent: создаст недостающие
  done
  echo "==> torrents/ и media/ структура готова в $DATA_ROOT"
else
  echo "==> $DATA_ROOT ещё не смонтирован — примонтируй NFS, затем запусти bootstrap повторно для torrents/"
fi

echo "==> Готово."
