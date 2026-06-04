#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  Standby entrypoint: bootstrap через pg_basebackup при пустом data dir,
#  иначе — обычный postgres start.
#
#  Запускается как entrypoint в docker-compose для pg-standby.
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

PGDATA=/var/lib/postgresql/data
: "${PG_PRIMARY_HOST:?PG_PRIMARY_HOST не задан}"
: "${PG_PRIMARY_PORT:=5432}"
: "${PG_REPLICATION_USER:?PG_REPLICATION_USER не задан}"
: "${PG_REPLICATION_PASSWORD:?PG_REPLICATION_PASSWORD не задан}"

# Если data dir не инициализирован — bootstrap через pg_basebackup
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "==> Standby bootstrap: pg_basebackup from ${PG_PRIMARY_HOST}:${PG_PRIMARY_PORT}"

  # Очистить (на случай мусора)
  rm -rf "$PGDATA"/* "$PGDATA"/.* 2>/dev/null || true
  mkdir -p "$PGDATA"
  chown postgres:postgres "$PGDATA"
  chmod 700 "$PGDATA"

  # pg_basebackup от имени replicator
  PGPASSWORD="$PG_REPLICATION_PASSWORD" su-exec postgres pg_basebackup \
    --host="$PG_PRIMARY_HOST" \
    --port="$PG_PRIMARY_PORT" \
    --username="$PG_REPLICATION_USER" \
    --pgdata="$PGDATA" \
    --wal-method=stream \
    --write-recovery-conf \
    --slot=standby_cdn \
    --create-slot \
    --checkpoint=fast \
    --progress \
    --verbose

  # standby.signal — режим standby (pg_basebackup -R создаёт, но дублируем)
  touch "$PGDATA/standby.signal"
  chown postgres:postgres "$PGDATA/standby.signal"

  echo "==> Standby bootstrap complete"
else
  echo "==> Existing data dir found, skipping bootstrap"
fi

# Передаём управление obычному postgres entrypoint
exec docker-entrypoint.sh "$@"
