#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  Nextcloud OIDC через user_oidc app — Keycloak realm family.
#
#  Запускать ВНУТРИ контейнера nextcloud-app под пользователем www-data:
#    docker exec -it -u www-data nextcloud-app bash
#    cd /var/www/html
#    bash /tmp/occ-setup.sh
#
#  Перед запуском:
#    - заполнить переменные KC_REALM_FAMILY, NC_CLIENT_SECRET
#    - убедиться, что user_oidc app установлен (occ app:install user_oidc если нет)
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

: "${FABRIC_DOMAIN:?FABRIC_DOMAIN не задан (например, example.com)}"
: "${NC_CLIENT_SECRET:?NC_CLIENT_SECRET не задан (из KC realm family → client nextcloud)}"

KC_ISSUER="https://login.${FABRIC_DOMAIN}/realms/family"
DISCOVERY="${KC_ISSUER}/.well-known/openid-configuration"

# Установка app (idempotent)
php occ app:install user_oidc 2>/dev/null || php occ app:enable user_oidc

# Существующий provider? — удалить и пересоздать
php occ user_oidc:provider:list --output=json 2>/dev/null \
  | grep -q '"identifier":"keycloak-family"' \
  && php occ user_oidc:provider:delete keycloak-family || true

# Создать provider
php occ user_oidc:provider \
  --clientid="nextcloud" \
  --clientsecret="$NC_CLIENT_SECRET" \
  --discoveryuri="$DISCOVERY" \
  --scope="openid profile email groups" \
  --unique-uid=1 \
  --mapping-uid="preferred_username" \
  --mapping-display-name="name" \
  --mapping-email="email" \
  --mapping-quota="" \
  --mapping-groups="groups" \
  keycloak-family

# Опционально: автоматическое создание пользователей
php occ config:app:set user_oidc auto_provision --value=1

echo "✓ Nextcloud OIDC provider keycloak-family создан."
echo "  Login URL: https://cloud.${FABRIC_DOMAIN}/index.php/apps/user_oidc/login/keycloak-family"
