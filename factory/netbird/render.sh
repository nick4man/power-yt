#!/usr/bin/env bash
# Рендер *.tpl → config.yaml + dashboard.env с подстановкой из .env.
# Реальный домен/секреты остаются ТОЛЬКО в отрендеренных файлах (gitignored).
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Нет .env — скопируй .env.example и заполни"; exit 1; }
set -a; . ./.env; set +a
: "${FABRIC_DOMAIN:?FABRIC_DOMAIN не задан}"
: "${NETBIRD_RELAY_AUTH_SECRET:?NETBIRD_RELAY_AUTH_SECRET не задан (openssl rand -base64 32)}"
: "${DATASTORE_ENCRYPTION_KEY:?DATASTORE_ENCRYPTION_KEY не задан (openssl rand -base64 32)}"

# config.yaml — несколько переменных; dashboard.env — только домен.
envsubst '${FABRIC_DOMAIN} ${NETBIRD_RELAY_AUTH_SECRET} ${DATASTORE_ENCRYPTION_KEY}' \
  < config.yaml.tpl > config.yaml
envsubst '${FABRIC_DOMAIN}' < dashboard.env.tpl > dashboard.env

echo "  ✓ config.yaml + dashboard.env отрендерены для домена: $FABRIC_DOMAIN"
