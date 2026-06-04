#!/usr/bin/env bash
# Рендер dynamic-templates/*.tpl → dynamic/*.yml с подстановкой ${FABRIC_DOMAIN} из .env.
# Реальный домен остаётся только в dynamic/ (gitignored), в git — лишь templates.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Нет .env — скопируй .env.example и заполни"; exit 1; }
set -a; . ./.env; set +a
: "${FABRIC_DOMAIN:?FABRIC_DOMAIN не задан в .env}"

mkdir -p dynamic
for tpl in dynamic-templates/*.tpl; do
  [ -e "$tpl" ] || continue
  out="dynamic/$(basename "${tpl%.tpl}")"
  FABRIC_DOMAIN="$FABRIC_DOMAIN" envsubst '${FABRIC_DOMAIN}' < "$tpl" > "$out"
  echo "  ✓ $out"
done
echo "Готово. dynamic/ отрендерен для домена: $FABRIC_DOMAIN"
