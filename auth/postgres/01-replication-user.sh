#!/usr/bin/env bash
# Создаёт пользователя для streaming replication при первом старте Postgres.
# Запускается из /docker-entrypoint-initdb.d/ — только на чистом DB volume.
# Идемпотентно: при повторном старте просто пропустится.

set -euo pipefail

: "${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD не задан в env}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
  DO
  \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
      CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${POSTGRES_REPLICATION_PASSWORD}';
      RAISE NOTICE '✓ replicator role created';
    ELSE
      RAISE NOTICE '⊙ replicator role уже существует';
    END IF;
  END
  \$\$;
EOSQL

echo "✓ replication user готов"
